#[derive(Debug, Clone, Default)]
pub struct ContainerPolicy {
    pub include_only: Vec<String>,
    pub exclude: Vec<String>,
    pub protect_network: bool,
    pub protect_socket: bool,
}

#[derive(Debug, Clone, Default)]
pub struct ContainerFacts {
    pub name: String,
    pub excluded_by_label: bool,
    pub compose_managed: bool,
    pub network_sensitive: bool,
    pub mounts_docker_socket: bool,
    pub network_mode: String,
    pub capabilities: Vec<String>,
    pub is_self: bool,
}

impl ContainerPolicy {
    pub fn allows(&self, facts: &ContainerFacts) -> bool {
        if facts.is_self || facts.excluded_by_label || facts.name.ends_with("_systower_bak") {
            return false;
        }
        if self.protect_socket && facts.mounts_docker_socket && self.include_only.is_empty() {
            return false;
        }
        let protected_network = facts.network_sensitive
            || facts.network_mode == "host"
            || facts.network_mode.starts_with("container:")
            || contains(&facts.capabilities, "NET_ADMIN")
            || contains(&facts.capabilities, "NET_RAW");
        if self.protect_network && protected_network && !contains(&self.include_only, &facts.name) {
            return false;
        }
        if !self.include_only.is_empty() {
            return contains(&self.include_only, &facts.name);
        }
        !contains(&self.exclude, &facts.name)
    }
}

fn contains(items: &[String], candidate: &str) -> bool {
    items
        .iter()
        .any(|item| item.eq_ignore_ascii_case(candidate))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn facts(name: &str) -> ContainerFacts {
        ContainerFacts {
            name: name.into(),
            ..Default::default()
        }
    }

    #[test]
    fn include_only_has_priority_over_exclude() {
        let policy = ContainerPolicy {
            include_only: vec!["api".into()],
            exclude: vec!["api".into()],
            ..Default::default()
        };
        assert!(policy.allows(&facts("API")));
        assert!(!policy.allows(&facts("web")));
    }

    #[test]
    fn protected_socket_is_skipped_without_explicit_include() {
        let policy = ContainerPolicy {
            protect_socket: true,
            ..Default::default()
        };
        assert!(!policy.allows(&ContainerFacts {
            mounts_docker_socket: true,
            ..facts("portainer")
        }));
    }

    #[test]
    fn compose_managed_containers_are_allowed_when_otherwise_safe() {
        let policy = ContainerPolicy::default();
        assert!(policy.allows(&ContainerFacts {
            compose_managed: true,
            ..facts("api")
        }));
    }

    #[test]
    fn explicit_include_overrides_network_protection() {
        let policy = ContainerPolicy {
            protect_network: true,
            include_only: vec!["vpn".into()],
            ..Default::default()
        };
        assert!(policy.allows(&ContainerFacts {
            network_sensitive: true,
            ..facts("vpn")
        }));
    }
}
