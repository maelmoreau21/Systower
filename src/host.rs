use std::fs::{self, OpenOptions};
use std::io::Write;
use std::{collections::HashMap, path::Path, process::Command};

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
    pub full_upgrade: bool,
}

#[derive(Debug, Error)]
pub enum HostError {
    #[error("unsupported Linux distribution: {0}")]
    Unsupported(String),
    #[error("host updates require explicit apply mode")]
    ApplyNotExplicit,
    #[error("cannot read host release information: {0}")]
    Io(#[from] std::io::Error),
    #[error("host command '{command}' failed with status {status}")]
    CommandFailed { command: String, status: String },
    #[error("host command '{0}' could not be started: {1}")]
    CommandStart(String, std::io::Error),
    #[error("host reboot failed: {0}")]
    RebootFailed(String),
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
        full_upgrade: false,
    })
}

fn host_command(command: &[&str]) -> Command {
    if Path::new("/proc/1/root").exists() {
        let mut process = Command::new("nsenter");
        process.args(["-t", "1", "-m", "-u", "-n", "-i", "--"]);
        process.args(command);
        process
    } else {
        let mut process = Command::new(command[0]);
        process.args(&command[1..]);
        process
    }
}

pub fn apply(plan: &SystemUpdatePlan, explicit_apply: bool) -> Result<(), HostError> {
    if !explicit_apply {
        return Err(HostError::ApplyNotExplicit);
    }
    let commands: Vec<Vec<&str>> = match plan.distribution {
        Distribution::Debian | Distribution::Ubuntu => {
            let upgrade = if plan.full_upgrade {
                "full-upgrade"
            } else {
                "upgrade"
            };
            vec![vec!["apt-get", "update"], vec!["apt-get", upgrade, "-y"]]
        }
        Distribution::Alpine => vec![vec!["apk", "upgrade", "--no-cache"]],
        Distribution::Arch => vec![vec!["pacman", "-Syu", "--noconfirm"]],
        Distribution::Fedora => vec![vec!["dnf", "upgrade", "-y"]],
        Distribution::Unknown => return Err(HostError::Unsupported("unknown".into())),
    };
    for command in commands {
        let status = host_command(&command)
            .status()
            .map_err(|source| HostError::CommandStart(command.join(" "), source))?;
        if !status.success() {
            return Err(HostError::CommandFailed {
                command: command.join(" "),
                status: status.to_string(),
            });
        }
    }
    Ok(())
}

pub fn reboot_required(plan: &SystemUpdatePlan) -> bool {
    let host_path = Path::new("/proc/1/root").join(&plan.reboot_required_path[1..]);
    host_path.exists() || Path::new(&plan.reboot_required_path).exists()
}

pub fn reboot(explicit_apply: bool) -> Result<(), HostError> {
    if !explicit_apply {
        return Err(HostError::ApplyNotExplicit);
    }
    let status = host_command(&["reboot"])
        .status()
        .map_err(|source| HostError::CommandStart("reboot".into(), source))?;
    if status.success() {
        Ok(())
    } else {
        Err(HostError::RebootFailed(status.to_string()))
    }
}

pub fn apply_network_immunity(explicit_apply: bool) -> Result<(), HostError> {
    if !explicit_apply {
        return Err(HostError::ApplyNotExplicit);
    }
    let root = Path::new("/proc/1/root");
    let root = if root.exists() { root } else { Path::new("/") };
    let dhcpcd = root.join("etc/dhcpcd.conf");
    if dhcpcd.exists() {
        let contents = fs::read_to_string(&dhcpcd)?;
        if !contents
            .lines()
            .any(|line| line.trim() == "denyinterfaces veth* docker* br-*")
        {
            let mut file = OpenOptions::new().append(true).open(dhcpcd)?;
            writeln!(file, "denyinterfaces veth* docker* br-*")?;
        }
    }
    let network_manager = root.join("etc/NetworkManager/conf.d");
    if network_manager.is_dir() {
        fs::write(
            network_manager.join("99-systower-docker.conf"),
            "[keyfile]\nunmanaged-devices=interface-name:veth*;interface-name:docker*;interface-name:br-*\n",
        )?;
    }
    Ok(())
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

    #[test]
    fn debian_plan_defaults_to_safe_upgrade() {
        let plan = plan("ID=debian\n").unwrap();
        assert!(!plan.full_upgrade);
        assert_eq!(plan.command[4], "upgrade");
    }
}
