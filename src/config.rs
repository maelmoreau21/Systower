use std::{env, time::Duration};

use serde::Serialize;
use thiserror::Error;

use crate::policy::ContainerPolicy;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("{variable} must be a boolean, got '{value}'")]
    Boolean { variable: String, value: String },
    #[error("{variable} must be a positive integer, got '{value}'")]
    Integer { variable: String, value: String },
    #[error("SYSTOWER_CRON must contain five fields")]
    InvalidCron,
    #[error("SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT must be greater than zero")]
    HealthcheckTimeout,
}

#[derive(Debug, Clone, Serialize)]
pub struct Config {
    pub cron: String,
    pub run_on_start: bool,
    pub docker_enabled: bool,
    pub docker_cleanup: bool,
    pub docker_prune: String,
    pub docker_prune_all: bool,
    pub docker_prune_until: String,
    pub docker_monitor_only: bool,
    pub docker_stop_timeout: u64,
    pub docker_healthcheck_timeout: u64,
    pub docker_protect_network_containers: bool,
    pub docker_protect_socket_containers: bool,
    pub docker_update_delay: u64,
    pub update_self: bool,
    pub system_enabled: bool,
    pub system_reboot: bool,
    pub dry_run: bool,
    pub log_level: String,
    pub include_only: Vec<String>,
    pub exclude: Vec<String>,
    pub state_file: String,
    pub docker_allow_no_healthcheck: bool,
    pub notify_enabled: bool,
    pub notify_webhook: String,
    pub notify_discord: String,
    pub notify_slack: String,
    pub notify_telegram_token: String,
    pub notify_telegram_chat: String,
}

impl Config {
    pub fn from_env() -> Result<Self, ConfigError> {
        let config = Self {
            cron: value("SYSTOWER_CRON", "0 4 * * *"),
            run_on_start: boolean("SYSTOWER_RUN_ON_START", true)?,
            docker_enabled: boolean("SYSTOWER_DOCKER_ENABLED", true)?,
            docker_cleanup: boolean("SYSTOWER_DOCKER_CLEANUP", true)?,
            docker_prune: value("SYSTOWER_DOCKER_PRUNE", "false"),
            docker_prune_all: boolean("SYSTOWER_DOCKER_PRUNE_ALL", false)?,
            docker_prune_until: value("SYSTOWER_DOCKER_PRUNE_UNTIL", ""),
            docker_monitor_only: boolean("SYSTOWER_DOCKER_MONITOR_ONLY", false)?,
            docker_stop_timeout: positive_integer("SYSTOWER_DOCKER_STOP_TIMEOUT", 30)?,
            docker_healthcheck_timeout: positive_integer(
                "SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT",
                60,
            )?,
            docker_protect_network_containers: boolean(
                "SYSTOWER_DOCKER_PROTECT_NETWORK_CONTAINERS",
                true,
            )?,
            docker_protect_socket_containers: boolean(
                "SYSTOWER_DOCKER_PROTECT_SOCKET_CONTAINERS",
                true,
            )?,
            docker_update_delay: positive_integer("SYSTOWER_DOCKER_UPDATE_DELAY", 2)?,
            update_self: boolean("SYSTOWER_UPDATE_SELF", false)?,
            system_enabled: boolean("SYSTOWER_SYSTEM_ENABLED", false)?,
            system_reboot: boolean("SYSTOWER_SYSTEM_REBOOT", false)?,
            dry_run: boolean("SYSTOWER_DRY_RUN", false)?,
            log_level: value("SYSTOWER_LOG_LEVEL", "info"),
            include_only: csv("SYSTOWER_DOCKER_INCLUDE_ONLY"),
            exclude: csv("SYSTOWER_DOCKER_EXCLUDE"),
            state_file: value("SYSTOWER_STATE_FILE", "./systower-state.jsonl"),
            docker_allow_no_healthcheck: boolean("SYSTOWER_DOCKER_ALLOW_NO_HEALTHCHECK", false)?,
            notify_enabled: boolean("SYSTOWER_NOTIFY_ENABLED", false)?,
            notify_webhook: value("SYSTOWER_NOTIFY_WEBHOOK", ""),
            notify_discord: value("SYSTOWER_NOTIFY_DISCORD", ""),
            notify_slack: value("SYSTOWER_NOTIFY_SLACK", ""),
            notify_telegram_token: value("SYSTOWER_NOTIFY_TELEGRAM_TOKEN", ""),
            notify_telegram_chat: value("SYSTOWER_NOTIFY_TELEGRAM_CHAT", ""),
        };
        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> Result<(), ConfigError> {
        if self.cron.split_whitespace().count() != 5 {
            return Err(ConfigError::InvalidCron);
        }
        if crate::scheduler::delay_until_next(&self.cron).is_err() {
            return Err(ConfigError::InvalidCron);
        }
        if self.docker_healthcheck_timeout == 0 {
            return Err(ConfigError::HealthcheckTimeout);
        }
        let _ = Duration::from_secs(self.docker_stop_timeout);
        Ok(())
    }

    pub fn policy(&self) -> ContainerPolicy {
        ContainerPolicy {
            include_only: self.include_only.clone(),
            exclude: self.exclude.clone(),
            protect_network: self.docker_protect_network_containers,
            protect_socket: self.docker_protect_socket_containers,
        }
    }
}

fn value(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_owned())
}

fn csv(name: &str) -> Vec<String> {
    value(name, "")
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_ascii_lowercase)
        .collect()
}

fn boolean(name: &str, default: bool) -> Result<bool, ConfigError> {
    let raw = env::var(name).unwrap_or_else(|_| default.to_string());
    match raw.to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Ok(true),
        "false" | "0" | "no" | "off" => Ok(false),
        _ => Err(ConfigError::Boolean {
            variable: name.to_owned(),
            value: raw,
        }),
    }
}

fn positive_integer(name: &str, default: u64) -> Result<u64, ConfigError> {
    let raw = env::var(name).unwrap_or_else(|_| default.to_string());
    raw.parse().map_err(|_| ConfigError::Integer {
        variable: name.to_owned(),
        value: raw,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_core_values() {
        let config = Config::from_env().expect("defaults should be valid");
        assert_eq!(config.cron, "0 4 * * *");
        assert!(config.docker_enabled);
        assert!(config.run_on_start);
        assert!(!config.system_enabled);
    }

    #[test]
    fn invalid_cron_is_rejected() {
        let config = Config {
            cron: "every night".into(),
            ..Config::from_env().unwrap()
        };
        assert!(matches!(config.validate(), Err(ConfigError::InvalidCron)));
    }
}
