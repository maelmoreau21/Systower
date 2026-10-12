use thiserror::Error;

use crate::{docker::ContainerSnapshot, policy::ContainerPolicy};

#[derive(Debug, Error, PartialEq, Eq)]
pub enum PlanError {
    #[error("target image reference is empty")]
    EmptyTargetImage,
    #[error("target image identity is empty")]
    EmptyTargetIdentity,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdatePlan {
    pub container_id: String,
    pub container_name: String,
    pub current_image: String,
    pub current_image_id: String,
    pub target_image: String,
    pub target_image_id: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HealthStatus {
    Healthy,
    Starting,
    Unhealthy,
    Running,
    Exited,
    Missing,
}

#[derive(Debug, Clone, Copy)]
pub struct HealthPolicy {
    pub allow_no_healthcheck: bool,
    pub stability_seconds: u64,
}

impl Default for HealthPolicy {
    fn default() -> Self {
        Self {
            allow_no_healthcheck: false,
            stability_seconds: 5,
        }
    }
}

pub fn health_is_acceptable(
    status: HealthStatus,
    has_healthcheck: bool,
    restart_count: u64,
    elapsed_seconds: u64,
    policy: HealthPolicy,
) -> bool {
    match status {
        HealthStatus::Healthy => restart_count == 0 && elapsed_seconds >= policy.stability_seconds,
        HealthStatus::Running => {
            !has_healthcheck
                && policy.allow_no_healthcheck
                && restart_count == 0
                && elapsed_seconds >= policy.stability_seconds
        }
        HealthStatus::Starting
        | HealthStatus::Unhealthy
        | HealthStatus::Exited
        | HealthStatus::Missing => false,
    }
}

impl UpdatePlan {
    pub fn for_container(
        container: &ContainerSnapshot,
        target_image: impl Into<String>,
        target_image_id: impl Into<String>,
        policy: &ContainerPolicy,
    ) -> Result<Option<Self>, PlanError> {
        if !policy.allows(&container.facts()) {
            return Ok(None);
        }
        let target_image = target_image.into();
        let target_image_id = target_image_id.into();
        if target_image.trim().is_empty() {
            return Err(PlanError::EmptyTargetImage);
        }
        if target_image_id.trim().is_empty() {
            return Err(PlanError::EmptyTargetIdentity);
        }
        if target_image_id == container.image_id {
            return Ok(None);
        }
        Ok(Some(Self {
            container_id: container.id.clone(),
            container_name: container.name.clone(),
            current_image: container.image.clone(),
            current_image_id: container.image_id.clone(),
            target_image,
            target_image_id,
        }))
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    fn container() -> ContainerSnapshot {
        ContainerSnapshot {
            id: "container-1".into(),
            name: "api".into(),
            image: "example/api:latest".into(),
            image_id: "sha256:old".into(),
            labels: HashMap::new(),
            state: "running".into(),
            status: "Up".into(),
            mounts_docker_socket: false,
            network_mode: String::new(),
            capabilities: Vec::new(),
        }
    }

    #[test]
    fn creates_plan_only_when_image_identity_changes() {
        let policy = ContainerPolicy::default();
        let plan =
            UpdatePlan::for_container(&container(), "example/api:latest", "sha256:new", &policy)
                .unwrap()
                .unwrap();
        assert_eq!(plan.current_image_id, "sha256:old");
        assert_eq!(plan.target_image_id, "sha256:new");
        assert!(UpdatePlan::for_container(
            &container(),
            "example/api:latest",
            "sha256:old",
            &policy,
        )
        .unwrap()
        .is_none());
    }

    #[test]
    fn refuses_unverified_target_identity() {
        let error = UpdatePlan::for_container(
            &container(),
            "example/api:latest",
            "",
            &ContainerPolicy::default(),
        )
        .unwrap_err();
        assert_eq!(error, PlanError::EmptyTargetIdentity);
    }

    #[test]
    fn excluded_container_never_gets_a_plan() {
        let mut facts = container();
        facts
            .labels
            .insert("systower.exclude".into(), "true".into());
        assert!(UpdatePlan::for_container(
            &facts,
            "example/api:latest",
            "sha256:new",
            &ContainerPolicy::default(),
        )
        .unwrap()
        .is_none());
    }

    #[test]
    fn starting_health_does_not_pass_after_timeout() {
        assert!(!health_is_acceptable(
            HealthStatus::Starting,
            true,
            0,
            120,
            HealthPolicy::default(),
        ));
    }

    #[test]
    fn running_without_healthcheck_requires_explicit_policy() {
        let policy = HealthPolicy {
            allow_no_healthcheck: true,
            stability_seconds: 10,
        };
        assert!(!health_is_acceptable(
            HealthStatus::Running,
            false,
            0,
            9,
            policy,
        ));
        assert!(health_is_acceptable(
            HealthStatus::Running,
            false,
            0,
            10,
            policy,
        ));
    }
}
