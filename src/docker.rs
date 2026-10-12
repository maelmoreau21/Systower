use std::collections::HashMap;

use bollard::{
    container::ListContainersOptions,
    models::{ContainerInspectResponse, ContainerSummary},
    Docker,
};
use thiserror::Error;

use crate::policy::{ContainerFacts, ContainerPolicy};

#[derive(Debug, Error)]
pub enum DockerError {
    #[error("Docker Engine is unavailable: {0}")]
    Api(#[from] bollard::errors::Error),
    #[error("Docker returned an invalid inspection response: {0}")]
    InvalidInspect(#[from] serde_json::Error),
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
        ContainerFacts {
            name: self.name.clone(),
            excluded_by_label: self
                .labels
                .get("systower.exclude")
                .is_some_and(|value| value.eq_ignore_ascii_case("true")),
            network_sensitive: image_and_name.contains("wireguard")
                || image_and_name.contains("tailscale")
                || image_and_name.contains("gluetun")
                || image_and_name.contains("pihole")
                || image_and_name.contains("adguard"),
            mounts_docker_socket: self.mounts_docker_socket,
            network_mode: self.network_mode.clone(),
            capabilities: self.capabilities.clone(),
            is_self: image_and_name.contains("systower"),
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

    pub async fn list_allowed(
        &self,
        policy: &ContainerPolicy,
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
            if policy.allows(&container.facts()) {
                allowed.push(container);
            }
        }
        Ok(allowed)
    }
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
}
