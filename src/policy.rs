use std::fmt;

#[derive(Debug, Clone, Default)]
pub struct ContainerPolicy {
    pub include_only: Vec<String>,
    pub exclude: Vec<String>,
    pub protect_network: bool,
    pub protect_socket: bool,
    pub allow_compose: bool,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkipReason {
    SelfContainer,
    ExcludedByLabel,
    ComposeManaged,
    BackupContainer,
    ExcludedByList,
    NotInIncludeOnly,
    ProtectedSocket,
    ProtectedNetwork,
}

impl fmt::Display for SkipReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::SelfContainer => write!(f, "self-container"),
            Self::ExcludedByLabel => write!(f, "systower.exclude=true label"),
            Self::ComposeManaged => {
                write!(
                    f,
                    "compose-managed (set SYSTOWER_DOCKER_ALLOW_COMPOSE=true to enable)"
                )
            }
            Self::BackupContainer => write!(f, "temporary systower backup container"),
            Self::ExcludedByList => write!(f, "matched SYSTOWER_DOCKER_EXCLUDE"),
            Self::NotInIncludeOnly => write!(f, "not in SYSTOWER_DOCKER_INCLUDE_ONLY"),
            Self::ProtectedSocket => write!(f, "mounts docker.sock (protected)"),
            Self::ProtectedNetwork => {
                write!(f, "network-sensitive or host/container network (protected)")
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PolicyDecision {
    Allowed,
    Skipped(SkipReason),
}

impl ContainerPolicy {
    pub fn evaluate(&self, facts: &ContainerFacts) -> PolicyDecision {
        if facts.is_self {
            return PolicyDecision::Skipped(SkipReason::SelfContainer);
        }
        if facts.excluded_by_label {
            return PolicyDecision::Skipped(SkipReason::ExcludedByLabel);
        }
        if facts.name.ends_with("_systower_bak") || facts.name.ends_with("_systower_updater") {
            return PolicyDecision::Skipped(SkipReason::BackupContainer);
        }
        if facts.compose_managed && !self.allow_compose {
            return PolicyDecision::Skipped(SkipReason::ComposeManaged);
        }
        // A selection list cannot override a safety exclusion.
        if matches_any(&self.exclude, &facts.name) {
            return PolicyDecision::Skipped(SkipReason::ExcludedByList);
        }
        if self.protect_socket && facts.mounts_docker_socket {
            return PolicyDecision::Skipped(SkipReason::ProtectedSocket);
        }
        let protected_network = facts.network_sensitive
            || facts.network_mode == "host"
            || facts.network_mode.starts_with("container:")
            || contains(&facts.capabilities, "NET_ADMIN")
            || contains(&facts.capabilities, "NET_RAW");
        if self.protect_network && protected_network {
            return PolicyDecision::Skipped(SkipReason::ProtectedNetwork);
        }
        if !self.include_only.is_empty() && !matches_any(&self.include_only, &facts.name) {
            return PolicyDecision::Skipped(SkipReason::NotInIncludeOnly);
        }
        PolicyDecision::Allowed
    }

    pub fn allows(&self, facts: &ContainerFacts) -> bool {
        self.evaluate(facts) == PolicyDecision::Allowed
    }
}

fn contains(items: &[String], candidate: &str) -> bool {
    items
        .iter()
        .any(|item| item.eq_ignore_ascii_case(candidate))
}

fn matches_any(patterns: &[String], candidate: &str) -> bool {
    patterns
        .iter()
        .any(|pattern| glob_match_ascii_icase(pattern, candidate))
}

fn glob_match_ascii_icase(pattern: &str, text: &str) -> bool {
    let p: Vec<u8> = pattern.bytes().map(|b| b.to_ascii_lowercase()).collect();
    let t: Vec<u8> = text.bytes().map(|b| b.to_ascii_lowercase()).collect();
    let (mut pi, mut ti) = (0usize, 0usize);
    let (mut star, mut match_ti) = (None, 0usize);

    while ti < t.len() {
        if pi < p.len() && (p[pi] == b'?' || p[pi] == t[ti]) {
            pi += 1;
            ti += 1;
        } else if pi < p.len() && p[pi] == b'*' {
            star = Some(pi);
            pi += 1;
            match_ti = ti;
        } else if let Some(star_idx) = star {
            pi = star_idx + 1;
            match_ti += 1;
            ti = match_ti;
        } else {
            return false;
        }
    }

    while pi < p.len() && p[pi] == b'*' {
        pi += 1;
    }
    pi == p.len()
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
    fn exclude_has_priority_over_include_only() {
        let policy = ContainerPolicy {
            include_only: vec!["api".into()],
            exclude: vec!["api".into()],
            ..Default::default()
        };
        assert!(!policy.allows(&facts("API")));
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
    fn compose_managed_containers_respect_allow_compose_policy() {
        let blocked = ContainerPolicy::default();
        assert_eq!(
            blocked.evaluate(&ContainerFacts {
                compose_managed: true,
                ..facts("api")
            }),
            PolicyDecision::Skipped(SkipReason::ComposeManaged)
        );
        let allowed = ContainerPolicy {
            allow_compose: true,
            ..Default::default()
        };
        assert!(allowed.allows(&ContainerFacts {
            compose_managed: true,
            ..facts("api")
        }));
    }

    #[test]
    fn glob_patterns_match_exclude_and_include_lists() {
        let policy = ContainerPolicy {
            exclude: vec!["dawarich*".into(), "*-db".into()],
            allow_compose: true,
            ..Default::default()
        };
        assert!(!policy.allows(&facts("dawarich_app")));
        assert!(!policy.allows(&facts("dawarich_valkey")));
        assert!(!policy.allows(&facts("authentik-db")));
        assert!(policy.allows(&facts("homarr")));
    }

    #[test]
    fn explicit_include_does_not_override_network_protection() {
        let policy = ContainerPolicy {
            protect_network: true,
            include_only: vec!["vpn".into()],
            ..Default::default()
        };
        assert!(!policy.allows(&ContainerFacts {
            network_sensitive: true,
            ..facts("vpn")
        }));
    }

    #[test]
    fn explicit_include_does_not_override_socket_protection() {
        let policy = ContainerPolicy {
            protect_socket: true,
            include_only: vec!["portainer".into()],
            ..Default::default()
        };
        assert!(!policy.allows(&ContainerFacts {
            mounts_docker_socket: true,
            ..facts("portainer")
        }));
    }

    #[test]
    fn excluded_label_always_wins() {
        let policy = ContainerPolicy {
            include_only: vec!["api".into()],
            ..Default::default()
        };
        assert!(!policy.allows(&ContainerFacts {
            excluded_by_label: true,
            ..facts("api")
        }));
    }
}
