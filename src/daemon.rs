use std::time::Duration;

use tracing::{error, info, warn};

use crate::{
    config::Config,
    docker::{DockerEngine, UpdateOptions},
    notify::{NotificationEvent, Notifier},
    scheduler::delay_until_next,
    state::{InstanceLock, StateJournal},
    update::HealthPolicy,
};

pub async fn run(config: Config) -> Result<(), Box<dyn std::error::Error>> {
    let _lock = InstanceLock::acquire(format!("{}.lock", config.state_file))?;
    let journal = StateJournal::open(&config.state_file)?;
    let engine = DockerEngine::connect().await?;
    let notifier = if config.notify_enabled {
        Some(Notifier::from_config(&config)?)
    } else {
        None
    };

    if config.run_on_start {
        run_cycle(&config, &engine, &journal, notifier.as_ref()).await;
    }

    loop {
        let delay = delay_until_next(&config.cron)?;
        info!(seconds = delay.as_secs(), "next update cycle scheduled");
        tokio::time::sleep(delay.max(Duration::from_secs(1))).await;
        run_cycle(&config, &engine, &journal, notifier.as_ref()).await;
    }
}

async fn run_cycle(
    config: &Config,
    engine: &DockerEngine,
    journal: &StateJournal,
    notifier: Option<&Notifier>,
) {
    let containers = match engine.list_allowed(&config.policy()).await {
        Ok(containers) => containers,
        Err(error) => {
            error!(%error, "cannot enumerate Docker containers");
            return;
        }
    };

    for container in containers {
        if config.dry_run || config.docker_monitor_only {
            info!(container = %container.name, image = %container.image, "update candidate detected");
            continue;
        }
        let event = match engine
            .update_container(
                &container.id,
                &container.image,
                journal,
                UpdateOptions {
                    health_policy: HealthPolicy {
                        allow_no_healthcheck: config.docker_allow_no_healthcheck,
                        stability_seconds: 5,
                    },
                    stop_timeout: config.docker_stop_timeout,
                    health_timeout: config.docker_healthcheck_timeout,
                    pull: true,
                    cleanup_old_image: config.docker_cleanup,
                },
            )
            .await
        {
            Ok(result) => {
                info!(container = %result.container_name, "container update completed");
                NotificationEvent {
                    event: "update.success".into(),
                    title: format!("Updated {}", result.container_name),
                    message: format!("Image identity: {}", result.target_image_id),
                }
            }
            Err(error) => {
                warn!(container = %container.name, %error, "container update failed");
                NotificationEvent {
                    event: "update.failure".into(),
                    title: format!("Update failed: {}", container.name),
                    message: error.to_string(),
                }
            }
        };
        if let Some(notifier) = notifier {
            if let Err(error) = notifier.send(&event).await {
                warn!(%error, "notification delivery failed");
            }
        }
        tokio::time::sleep(Duration::from_secs(config.docker_update_delay)).await;
    }
}
