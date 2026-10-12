use std::{
    collections::HashMap,
    time::{SystemTime, UNIX_EPOCH},
};

use bollard::{
    container::{
        Config as DockerConfig, CreateContainerOptions, ListContainersOptions, NetworkingConfig,
        RemoveContainerOptions, RenameContainerOptions, StartContainerOptions,
        StopContainerOptions,
    },
    image::{CreateImageOptions, PruneImagesOptions, RemoveImageOptions},
    models::{ContainerInspectResponse, ContainerSummary, EndpointSettings},
    Docker,
};
use futures_util::StreamExt;
use thiserror::Error;

use crate::policy::{ContainerFacts, ContainerPolicy};
use crate::{
    state::{StateError, StateJournal, Transaction, TransactionState},
    update::{health_is_acceptable, HealthPolicy, HealthStatus},
};

#[derive(Debug, Error)]
pub enum DockerError {
    #[error("Docker Engine is unavailable: {0}")]
    Api(#[from] bollard::errors::Error),
    #[error("Docker returned an invalid inspection response: {0}")]
    InvalidInspect(#[from] serde_json::Error),
    #[error("Docker did not return an image identity for '{0}'")]
    MissingImageIdentity(String),
    #[error("Docker update failed: {0}")]
    UpdateFailed(String),
    #[error("rollback failed: {0}")]
    RollbackFailed(String),
    #[error("state journal error: {0}")]
    State(#[from] StateError),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContainerSnapshot {
    pub id: String,
    pub name: String,
    pub image: String,
    pub image_id: String,
    pub labels: HashMap<String, String>,
    pub state: String,
    pub status: String,
    pub mounts_docker_socket: bool,
    pub network_mode: String,
    pub capabilities: Vec<String>,
}

pub struct RecreationConfig {
    pub config: DockerConfig<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateResult {
    pub container_name: String,
    pub state: TransactionState,
    pub target_image_id: String,
}

#[derive(Debug, Clone, Copy)]
pub struct UpdateOptions {
    pub health_policy: HealthPolicy,
    pub stop_timeout: u64,
    pub health_timeout: u64,
    pub pull: bool,
    pub cleanup_old_image: bool,
}

impl RecreationConfig {
    pub fn from_inspect(
        inspect: &ContainerInspectResponse,
        target_image: impl Into<String>,
    ) -> Result<Self, DockerError> {
        let value = serde_json::to_value(inspect)?;
        let config_value = value
            .get("Config")
            .cloned()
            .ok_or_else(|| DockerError::MissingImageIdentity("container config".into()))?;
        let mut config: DockerConfig<String> = serde_json::from_value(config_value)?;
        config.image = Some(target_image.into());
        if let Some(host_config) = value.get("HostConfig") {
            config.host_config = Some(serde_json::from_value(host_config.clone())?);
        }
        if let Some(networks) = value.pointer("/NetworkSettings/Networks") {
            let endpoints: std::collections::HashMap<String, EndpointSettings> =
                serde_json::from_value(networks.clone())?;
            config.networking_config = Some(NetworkingConfig {
                endpoints_config: endpoints,
            });
        }
        Ok(Self { config })
    }
}

impl ContainerSnapshot {
    pub fn from_summary(summary: ContainerSummary) -> Option<Self> {
        let id = summary.id?;
        let name = summary
            .names
            .unwrap_or_default()
            .into_iter()
            .next()
            .map(|name| name.trim_start_matches('/').to_owned())?;
        Some(Self {
            id,
            name,
            image: summary.image.unwrap_or_default(),
            image_id: summary.image_id.unwrap_or_default(),
            labels: summary.labels.unwrap_or_default(),
            state: summary.state.unwrap_or_default(),
            status: summary.status.unwrap_or_default(),
            mounts_docker_socket: false,
            network_mode: String::new(),
            capabilities: Vec::new(),
        })
    }

    fn apply_inspect(
        &mut self,
        inspect: &ContainerInspectResponse,
    ) -> Result<(), serde_json::Error> {
        let value = serde_json::to_value(inspect)?;
        if let Some(name) = value.get("Name").and_then(|name| name.as_str()) {
            self.name = name.trim_start_matches('/').to_owned();
        }
        if let Some(image) = value.get("Image").and_then(|image| image.as_str()) {
            self.image_id = image.to_owned();
        }
        if let Some(labels) = value
            .pointer("/Config/Labels")
            .and_then(|labels| labels.as_object())
        {
            self.labels.extend(labels.iter().filter_map(|(key, value)| {
                value.as_str().map(|value| (key.clone(), value.to_owned()))
            }));
        }
        self.network_mode = value
            .pointer("/HostConfig/NetworkMode")
            .and_then(|mode| mode.as_str())
            .unwrap_or_default()
            .to_owned();
        self.capabilities = value
            .pointer("/HostConfig/CapAdd")
            .and_then(|caps| caps.as_array())
            .map(|caps| {
                caps.iter()
                    .filter_map(|cap| cap.as_str().map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default();
        self.mounts_docker_socket = value
            .get("Mounts")
            .and_then(|mounts| mounts.as_array())
            .map(|mounts| {
                mounts.iter().any(|mount| {
                    mount.get("Source").and_then(|source| source.as_str())
                        == Some("/var/run/docker.sock")
                        || mount
                            .get("Destination")
                            .and_then(|destination| destination.as_str())
                            == Some("/var/run/docker.sock")
                })
            })
            .unwrap_or(false);
        Ok(())
    }

    pub fn facts(&self) -> ContainerFacts {
        let image_and_name = format!("{} {}", self.name, self.image).to_ascii_lowercase();
        let image_name = self
            .image
            .rsplit('/')
            .next()
            .unwrap_or_default()
            .split(':')
            .next()
            .unwrap_or_default();
        let compose_service_is_self = self
            .labels
            .get("com.docker.compose.service")
            .is_some_and(|service| service.eq_ignore_ascii_case("systower"));
        ContainerFacts {
            name: self.name.clone(),
            excluded_by_label: self
                .labels
                .get("systower.exclude")
                .is_some_and(|value| value.eq_ignore_ascii_case("true")),
            compose_managed: self.labels.contains_key("com.docker.compose.project")
                || self.labels.contains_key("com.docker.compose.service"),
            network_sensitive: image_and_name.contains("wireguard")
                || image_and_name.contains("tailscale")
                || image_and_name.contains("gluetun")
                || image_and_name.contains("pihole")
                || image_and_name.contains("adguard"),
            mounts_docker_socket: self.mounts_docker_socket,
            network_mode: self.network_mode.clone(),
            capabilities: self.capabilities.clone(),
            is_self: self.name.eq_ignore_ascii_case("systower")
                || compose_service_is_self
                || image_name.eq_ignore_ascii_case("systower"),
        }
    }
}

pub struct DockerEngine {
    client: Docker,
}

impl DockerEngine {
    pub async fn connect() -> Result<Self, DockerError> {
        let client = Docker::connect_with_local_defaults()?;
        client.ping().await?;
        Ok(Self { client })
    }

    pub async fn recover_interrupted(&self, journal: &StateJournal) -> Result<(), DockerError> {
        for record in journal.interrupted()? {
            if record.state == TransactionState::Planned {
                continue;
            }
            let mut transaction = Transaction::from_record(record.clone());
            if transaction.record().state == TransactionState::ImagePulled {
                transition(&mut transaction, TransactionState::RollingBack, journal)?;
                transition(&mut transaction, TransactionState::RolledBack, journal)?;
                continue;
            }
            let inspected = self
                .client
                .inspect_container(&record.container_id, None)
                .await;
            let current_name = inspected.ok().and_then(|inspect| {
                serde_json::to_value(inspect)
                    .ok()?
                    .get("Name")
                    .and_then(|name| name.as_str())
                    .map(|name| name.trim_start_matches('/').to_owned())
            });
            let original_name = current_name
                .as_deref()
                .and_then(|name| name.strip_suffix("_systower_bak"))
                .or(current_name.as_deref())
                .map(str::to_owned);
            let Some(original_name) = original_name else {
                if transaction.record().state != TransactionState::RollingBack {
                    transition(&mut transaction, TransactionState::RollingBack, journal)?;
                }
                transition(&mut transaction, TransactionState::RollbackFailed, journal)?;
                continue;
            };
            let backup_name = format!("{original_name}_systower_bak");
            let backup_exists = self
                .client
                .inspect_container(&backup_name, None)
                .await
                .is_ok();
            if !backup_exists {
                if transaction.record().state != TransactionState::RollingBack {
                    transition(&mut transaction, TransactionState::RollingBack, journal)?;
                }
                transition(&mut transaction, TransactionState::RollbackFailed, journal)?;
                continue;
            }
            let _ = self
                .client
                .remove_container(
                    &original_name,
                    Some(RemoveContainerOptions {
                        force: true,
                        link: false,
                        v: false,
                    }),
                )
                .await;
            if transaction.record().state != TransactionState::RollingBack {
                transition(&mut transaction, TransactionState::RollingBack, journal)?;
            }
            if let Err(error) = self
                .client
                .rename_container(
                    &backup_name,
                    RenameContainerOptions {
                        name: &original_name,
                    },
                )
                .await
            {
                transition(&mut transaction, TransactionState::RollbackFailed, journal)?;
                return Err(DockerError::RollbackFailed(error.to_string()));
            }
            if let Err(error) = self
                .client
                .start_container::<String>(&original_name, None::<StartContainerOptions<String>>)
                .await
            {
                transition(&mut transaction, TransactionState::RollbackFailed, journal)?;
                return Err(DockerError::RollbackFailed(error.to_string()));
            }
            if let Err(error) = self.verify_restored_container(&original_name).await {
                transition(&mut transaction, TransactionState::RollbackFailed, journal)?;
                return Err(DockerError::RollbackFailed(error));
            }
            transition(&mut transaction, TransactionState::RolledBack, journal)?;
        }
        Ok(())
    }

    pub async fn list_allowed(
        &self,
        policy: &ContainerPolicy,
    ) -> Result<Vec<ContainerSnapshot>, DockerError> {
        self.list_allowed_with_self(policy, false).await
    }

    pub async fn list_allowed_with_self(
        &self,
        policy: &ContainerPolicy,
        include_self: bool,
    ) -> Result<Vec<ContainerSnapshot>, DockerError> {
        let summaries = self
            .client
            .list_containers(Some(ListContainersOptions::<String> {
                all: false,
                ..Default::default()
            }))
            .await?;
        let mut allowed = Vec::new();
        for summary in summaries {
            let Some(mut container) = ContainerSnapshot::from_summary(summary) else {
                continue;
            };
            let inspect = self.client.inspect_container(&container.id, None).await?;
            container.apply_inspect(&inspect)?;
            let facts = container.facts();
            if (include_self && facts.is_self && !facts.excluded_by_label)
                || (!facts.is_self && policy.allows(&facts))
            {
                allowed.push(container);
            }
        }
        Ok(allowed)
    }

    pub async fn pull_image(&self, image: &str) -> Result<String, DockerError> {
        let image = image.trim();
        if image.is_empty() {
            return Err(DockerError::MissingImageIdentity(image.to_owned()));
        }
        let options = CreateImageOptions {
            from_image: image,
            ..Default::default()
        };
        let mut stream = self.client.create_image(Some(options), None, None);
        while let Some(result) = stream.next().await {
            result?;
        }
        let inspected = self.client.inspect_image(image).await?;
        let value = serde_json::to_value(inspected)?;
        let identity = value
            .get("Id")
            .and_then(|id| id.as_str())
            .filter(|id| !id.is_empty())
            .ok_or_else(|| DockerError::MissingImageIdentity(image.to_owned()))?;
        Ok(identity.to_owned())
    }

    pub async fn prune_images(
        &self,
        prune_all: bool,
        until: Option<&str>,
    ) -> Result<u64, DockerError> {
        let mut filters = HashMap::new();
        filters.insert("dangling".to_owned(), vec![(!prune_all).to_string()]);
        if let Some(until) = until.filter(|value| !value.is_empty()) {
            filters.insert("until".to_owned(), vec![until.to_owned()]);
        }
        let result = self
            .client
            .prune_images(Some(PruneImagesOptions { filters }))
            .await?;
        Ok(result.space_reclaimed.unwrap_or(0).max(0) as u64)
    }

    pub async fn recreation_config(
        &self,
        container_id: &str,
        target_image: impl Into<String>,
    ) -> Result<RecreationConfig, DockerError> {
        let inspect = self.client.inspect_container(container_id, None).await?;
        RecreationConfig::from_inspect(&inspect, target_image)
    }

    async fn inspect_image_identity(&self, image: &str) -> Result<String, DockerError> {
        let inspected = self.client.inspect_image(image).await?;
        let value = serde_json::to_value(inspected)?;
        value
            .get("Id")
            .and_then(|id| id.as_str())
            .filter(|id| !id.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| DockerError::MissingImageIdentity(image.to_owned()))
    }

    pub async fn update_container(
        &self,
        container_id: &str,
        target_image: &str,
        journal: &StateJournal,
        options: UpdateOptions,
    ) -> Result<UpdateResult, DockerError> {
        let inspect = self.client.inspect_container(container_id, None).await?;
        let value = serde_json::to_value(&inspect)?;
        let name = value
            .get("Name")
            .and_then(|name| name.as_str())
            .unwrap_or_default()
            .trim_start_matches('/')
            .to_owned();
        if name.is_empty() {
            return Err(DockerError::UpdateFailed("container has no name".into()));
        }
        if value
            .pointer("/HostConfig/AutoRemove")
            .and_then(|value| value.as_bool())
            .unwrap_or(false)
        {
            return Err(DockerError::UpdateFailed(
                "containers with AutoRemove=true cannot be safely rolled back".into(),
            ));
        }
        let old_image_id = value
            .get("Image")
            .and_then(|image| image.as_str())
            .unwrap_or_default()
            .to_owned();
        let target_image_id = if options.pull {
            self.pull_image(target_image).await?
        } else {
            self.inspect_image_identity(target_image).await?
        };
        if target_image_id == old_image_id {
            return Ok(UpdateResult {
                container_name: name,
                state: TransactionState::Committed,
                target_image_id,
            });
        }

        let transaction_id = format!(
            "tx-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(|error| DockerError::UpdateFailed(error.to_string()))?
                .as_nanos()
        );
        let mut transaction = Transaction::new(
            transaction_id,
            container_id.to_owned(),
            target_image.to_owned(),
        );
        journal.append(transaction.record())?;
        transition(&mut transaction, TransactionState::ImagePulled, journal)?;
        let recreation = RecreationConfig::from_inspect(&inspect, target_image)?;
        let backup_name = format!("{name}_systower_bak");
        if self
            .client
            .inspect_container(&backup_name, None)
            .await
            .is_ok()
        {
            return Err(DockerError::UpdateFailed(format!(
                "backup container '{backup_name}' already exists"
            )));
        }

        let running = value
            .pointer("/State/Running")
            .and_then(|running| running.as_bool())
            .unwrap_or(false);
        if running {
            self.client
                .stop_container(
                    container_id,
                    Some(StopContainerOptions {
                        t: options.stop_timeout as i64,
                    }),
                )
                .await?;
        }
        self.client
            .rename_container(
                container_id,
                RenameContainerOptions {
                    name: backup_name.as_str(),
                },
            )
            .await?;
        transition(&mut transaction, TransactionState::BackupCreated, journal)?;

        let created = match self
            .client
            .create_container(
                Some(CreateContainerOptions {
                    name: name.as_str(),
                    platform: None,
                }),
                recreation.config,
            )
            .await
        {
            Ok(created) => created,
            Err(error) => {
                return self
                    .rollback_after_failure(
                        &name,
                        &backup_name,
                        &mut transaction,
                        journal,
                        format!("container creation failed: {error}"),
                    )
                    .await;
            }
        };
        transition(
            &mut transaction,
            TransactionState::ReplacementStarted,
            journal,
        )?;
        if let Err(error) = self
            .client
            .start_container::<String>(&created.id, None::<StartContainerOptions<String>>)
            .await
        {
            return self
                .rollback_after_failure(
                    &name,
                    &backup_name,
                    &mut transaction,
                    journal,
                    format!("replacement start failed: {error}"),
                )
                .await;
        }
        transition(&mut transaction, TransactionState::HealthChecking, journal)?;
        if let Err(error) = self
            .wait_for_health(&name, options.health_timeout, options.health_policy)
            .await
        {
            return self
                .rollback_after_failure(&name, &backup_name, &mut transaction, journal, error)
                .await;
        }
        self.client
            .remove_container(
                &backup_name,
                Some(RemoveContainerOptions {
                    force: true,
                    link: false,
                    v: false,
                }),
            )
            .await?;
        if options.cleanup_old_image {
            if let Err(error) = self
                .client
                .remove_image(
                    &old_image_id,
                    Some(RemoveImageOptions {
                        force: false,
                        noprune: true,
                    }),
                    None,
                )
                .await
            {
                tracing::warn!(image = %old_image_id, %error, "old image retention cleanup skipped");
            }
        }
        transition(&mut transaction, TransactionState::Committed, journal)?;
        Ok(UpdateResult {
            container_name: name,
            state: transaction.record().state.clone(),
            target_image_id,
        })
    }

    async fn wait_for_health(
        &self,
        container: &str,
        timeout: u64,
        policy: HealthPolicy,
    ) -> Result<(), String> {
        let started = tokio::time::Instant::now();
        loop {
            let inspect = self
                .client
                .inspect_container(container, None)
                .await
                .map_err(|error| error.to_string())?;
            let value = serde_json::to_value(inspect).map_err(|error| error.to_string())?;
            let state = value
                .pointer("/State/Status")
                .and_then(|status| status.as_str())
                .unwrap_or("missing");
            let health = value
                .pointer("/State/Health/Status")
                .and_then(|status| status.as_str());
            let status = match (state, health) {
                ("running", Some("healthy")) => HealthStatus::Healthy,
                ("running", Some("starting")) => HealthStatus::Starting,
                ("running", Some("unhealthy")) => HealthStatus::Unhealthy,
                ("running", None) => HealthStatus::Running,
                ("exited", _) | ("dead", _) => HealthStatus::Exited,
                _ => HealthStatus::Missing,
            };
            let restart_count = value
                .pointer("/RestartCount")
                .and_then(|count| count.as_u64())
                .unwrap_or(0);
            let has_healthcheck = value
                .pointer("/Config/Healthcheck")
                .is_some_and(|health| !health.is_null());
            if health_is_acceptable(
                status,
                has_healthcheck,
                restart_count,
                started.elapsed().as_secs(),
                policy,
            ) {
                return Ok(());
            }
            if started.elapsed().as_secs() >= timeout
                || matches!(
                    status,
                    HealthStatus::Unhealthy | HealthStatus::Exited | HealthStatus::Missing
                )
            {
                return Err(format!("health check failed with state '{state}'"));
            }
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
    }

    async fn rollback_after_failure(
        &self,
        name: &str,
        backup_name: &str,
        transaction: &mut Transaction,
        journal: &StateJournal,
        reason: String,
    ) -> Result<UpdateResult, DockerError> {
        transition(transaction, TransactionState::RollingBack, journal)?;
        let _ = self
            .client
            .remove_container(
                name,
                Some(RemoveContainerOptions {
                    force: true,
                    link: false,
                    v: false,
                }),
            )
            .await;
        if let Err(error) = self
            .client
            .rename_container(backup_name, RenameContainerOptions { name })
            .await
        {
            transition(transaction, TransactionState::RollbackFailed, journal)?;
            return Err(DockerError::RollbackFailed(format!(
                "{reason}; rename failed: {error}"
            )));
        }
        if let Err(error) = self
            .client
            .start_container::<String>(name, None::<StartContainerOptions<String>>)
            .await
        {
            transition(transaction, TransactionState::RollbackFailed, journal)?;
            return Err(DockerError::RollbackFailed(format!(
                "{reason}; restore start failed: {error}"
            )));
        }
        if let Err(error) = self.verify_restored_container(name).await {
            transition(transaction, TransactionState::RollbackFailed, journal)?;
            return Err(DockerError::RollbackFailed(format!("{reason}; {error}")));
        }
        transition(transaction, TransactionState::RolledBack, journal)?;
        Err(DockerError::UpdateFailed(format!(
            "{reason}; rollback verified"
        )))
    }

    async fn verify_restored_container(&self, name: &str) -> Result<(), String> {
        let restored = self
            .client
            .inspect_container(name, None)
            .await
            .map_err(|error| format!("restored container inspection failed: {error}"))?;
        let restored_value = serde_json::to_value(restored)
            .map_err(|error| format!("restored container inspection was invalid: {error}"))?;
        if restored_value
            .pointer("/State/Running")
            .and_then(|running| running.as_bool())
            != Some(true)
        {
            return Err("restored container is not running".into());
        }
        let health = restored_value.pointer("/State/Health/Status");
        if health.is_some() && health.and_then(|status| status.as_str()) != Some("healthy") {
            return Err(format!(
                "restored container health is '{}', not healthy",
                health
                    .and_then(|status| status.as_str())
                    .unwrap_or("unknown")
            ));
        }
        if restored_value
            .pointer("/RestartCount")
            .and_then(|count| count.as_u64())
            .unwrap_or(0)
            != 0
        {
            return Err("restored container is restarting".into());
        }
        Ok(())
    }
}

fn transition(
    transaction: &mut Transaction,
    state: TransactionState,
    journal: &StateJournal,
) -> Result<(), DockerError> {
    transaction.transition(state)?;
    journal.append(transaction.record())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summary_becomes_safe_snapshot_and_policy_facts() {
        let summary = ContainerSummary {
            id: Some("abc123".into()),
            names: Some(vec!["/api".into()]),
            image: Some("example/api:latest".into()),
            image_id: Some("sha256:old".into()),
            labels: Some(HashMap::from([("systower.exclude".into(), "true".into())])),
            state: Some("running".into()),
            status: Some("Up 2 minutes".into()),
            ..Default::default()
        };
        let snapshot = ContainerSnapshot::from_summary(summary).unwrap();
        assert_eq!(snapshot.name, "api");
        assert_eq!(snapshot.image_id, "sha256:old");
        assert!(snapshot.facts().excluded_by_label);
    }

    #[test]
    fn summary_without_id_cannot_be_updated() {
        let summary = ContainerSummary {
            names: Some(vec!["/missing-id".into()]),
            ..Default::default()
        };
        assert!(ContainerSnapshot::from_summary(summary).is_none());
    }

    #[test]
    fn similarly_named_container_is_not_mistaken_for_systower() {
        let summary = ContainerSummary {
            id: Some("abc123".into()),
            names: Some(vec!["/systower-v2-test".into()]),
            image: Some("alpine:3.20".into()),
            ..Default::default()
        };
        let snapshot = ContainerSnapshot::from_summary(summary).unwrap();
        assert!(!snapshot.facts().is_self);
    }
}
