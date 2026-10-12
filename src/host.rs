use std::collections::HashMap;

use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Distribution {
    Debian,
    Ubuntu,
    Alpine,
    Arch,
    Fedora,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SystemUpdatePlan {
    pub distribution: Distribution,
    pub command: Vec<String>,
    pub reboot_required_path: String,
}

#[derive(Debug, Error)]
pub enum HostError {
    #[error("unsupported Linux distribution: {0}")]
    Unsupported(String),
    #[error("host updates require explicit apply mode")]
    ApplyNotExplicit,
}

pub fn parse_os_release(contents: &str) -> HashMap<String, String> {
    contents
        .lines()
        .filter_map(|line| {
            let (key, value) = line.split_once('=')?;
            let value = value.trim_matches('"').trim_matches('\'').to_owned();
            Some((key.to_owned(), value))
        })
        .collect()
}

pub fn distribution(os_release: &HashMap<String, String>) -> Distribution {
    match os_release.get("ID").map(String::as_str) {
        Some("debian") => Distribution::Debian,
        Some("ubuntu") => Distribution::Ubuntu,
        Some("alpine") => Distribution::Alpine,
        Some("arch") => Distribution::Arch,
        Some("fedora") => Distribution::Fedora,
        _ => Distribution::Unknown,
    }
}

pub fn plan(contents: &str) -> Result<SystemUpdatePlan, HostError> {
    let release = parse_os_release(contents);
    let distribution = distribution(&release);
    let command = match distribution {
        Distribution::Debian | Distribution::Ubuntu => vec![
            "apt-get".into(),
            "update".into(),
            "&&".into(),
            "apt-get".into(),
            "upgrade".into(),
            "-y".into(),
        ],
        Distribution::Alpine => vec!["apk".into(), "upgrade".into(), "--no-cache".into()],
        Distribution::Arch => vec!["pacman".into(), "-Syu".into(), "--noconfirm".into()],
        Distribution::Fedora => vec!["dnf".into(), "upgrade".into(), "-y".into()],
        Distribution::Unknown => {
            return Err(HostError::Unsupported(
                release
                    .get("ID")
                    .cloned()
                    .unwrap_or_else(|| "unknown".into()),
            ))
        }
    };
    Ok(SystemUpdatePlan {
        distribution,
        command,
        reboot_required_path: "/var/run/reboot-required".into(),
    })
}

pub fn apply(_plan: &SystemUpdatePlan, explicit_apply: bool) -> Result<(), HostError> {
    if !explicit_apply {
        return Err(HostError::ApplyNotExplicit);
    }
    Err(HostError::ApplyNotExplicit)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_supported_distributions() {
        assert_eq!(
            distribution(&parse_os_release("ID=ubuntu\nVERSION_ID=24.04")),
            Distribution::Ubuntu
        );
        assert_eq!(
            distribution(&parse_os_release("ID=alpine\n")),
            Distribution::Alpine
        );
    }

    #[test]
    fn plans_without_executing_host_commands() {
        let plan = plan("ID=debian\n").unwrap();
        assert_eq!(plan.command[0], "apt-get");
        assert!(apply(&plan, false).is_err());
    }

    #[test]
    fn rejects_unknown_distribution() {
        assert!(matches!(plan("ID=plan9\n"), Err(HostError::Unsupported(_))));
    }
}
