use std::time::Duration;

use tracing::{error, info, warn};

use crate::{
    compose::{self, ComposePlan},
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
    let engine = if config.docker_enabled {
        Some(DockerEngine::connect().await?)
    } else {
        info!("Docker updates disabled by configuration");
        None
    };
    if !config.dry_run && !config.docker_monitor_only {
        if let Some(engine) = engine.as_ref() {
            if let Err(error) = engine
                .recover_interrupted(&journal, config.docker_rollback_healthcheck_timeout)
                .await
            {
                warn!(%error, "interrupted Docker transaction recovery failed");
            }
        }
    }
    let notifier = if config.notify_enabled {
        Some(Notifier::from_config(&config)?)
    } else {
        None
    };

    if config.run_on_start && run_cycle(&config, engine.as_ref(), &journal, notifier.as_ref()).await
    {
        return Ok(());
    }

    loop {
        let delay = delay_until_next(&config.cron)?;
        info!(seconds = delay.as_secs(), "next update cycle scheduled");
        tokio::select! {
            _ = tokio::time::sleep(delay.max(Duration::from_secs(1))) => {}
            _ = shutdown_signal() => {
                info!("shutdown signal received; stopping daemon");
                return Ok(());
            }
        }
        if run_cycle(&config, engine.as_ref(), &journal, notifier.as_ref()).await {
            return Ok(());
        }
    }
}

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        match signal(SignalKind::terminate()) {
            Ok(mut sigterm) => {
                tokio::select! {
                    _ = tokio::signal::ctrl_c() => {}
                    _ = sigterm.recv() => {}
                }
            }
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}

async fn run_cycle(
    config: &Config,
    engine: Option<&DockerEngine>,
    journal: &StateJournal,
    notifier: Option<&Notifier>,
) -> bool {
    let Some(engine) = engine else {
        run_compose_updates(config, notifier).await;
        run_system_update(config).await;
        return false;
    };

    let evaluated = match engine.list_evaluated(&config.policy()).await {
        Ok(evaluated) => evaluated,
        Err(error) => {
            error!(%error, "cannot enumerate Docker containers");
            run_compose_updates(config, notifier).await;
            run_system_update(config).await;
            return false;
        }
    };

    let mut skipped_count = evaluated.skipped.len();
    for (name, reason) in &evaluated.skipped {
        info!(container = %name, reason = %reason, "container skipped by policy");
    }

    let compose_managed_services: std::collections::HashSet<String> = if config.compose_enabled {
        config
            .compose_targets()
            .unwrap_or_default()
            .into_iter()
            .flat_map(|target| target.services)
            .map(|service| service.to_ascii_lowercase())
            .collect()
    } else {
        std::collections::HashSet::new()
    };

    let mut checked_count = 0usize;
    let mut updated_count = 0usize;
    let mut unchanged_count = 0usize;
    let mut failed_count = 0usize;

    for container in evaluated.allowed {
        if let Some(service) = container.labels.get("com.docker.compose.service") {
            if compose_managed_services.contains(&service.to_ascii_lowercase()) {
                info!(container = %container.name, %service, "container handled by explicit compose target; skipping standalone update");
                skipped_count += 1;
                continue;
            }
        }
        checked_count += 1;
        if config.dry_run || config.docker_monitor_only {
            info!(container = %container.name, image = %container.image, "eligible container detected; image freshness not checked");
            continue;
        }
        let event = match engine
            .update_container(
                &container.id,
                &container.image,
                journal,
                UpdateOptions {
                    policy: config.policy(),
                    health_policy: HealthPolicy {
                        allow_no_healthcheck: config.docker_allow_no_healthcheck,
                        stability_seconds: 5,
                    },
                    stop_timeout: config.docker_stop_timeout,
                    health_timeout: config.docker_healthcheck_timeout,
                    rollback_health_timeout: config.docker_rollback_healthcheck_timeout,
                    pull: true,
                    cleanup_old_image: config.docker_cleanup,
                },
            )
            .await
        {
            Ok(result) => {
                if let Some(reason) = result.skipped_reason {
                    info!(container = %result.container_name, %reason, "container skipped");
                    skipped_count += 1;
                    continue;
                }
                if !result.changed {
                    info!(container = %result.container_name, "image unchanged; no update performed");
                    unchanged_count += 1;
                    continue;
                }
                updated_count += 1;
                info!(container = %result.container_name, "container update completed");
                NotificationEvent {
                    event: "update.success".into(),
                    title: format!("Updated {}", result.container_name),
                    message: format!("Image identity: {}", result.target_image_id),
                }
            }
            Err(error) => {
                failed_count += 1;
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

    if !config.dry_run
        && !config.docker_monitor_only
        && (config.docker_prune.eq_ignore_ascii_case("true")
            || config.docker_prune.eq_ignore_ascii_case("all")
            || config.docker_prune_all)
    {
        let prune_all = config.docker_prune.eq_ignore_ascii_case("all") || config.docker_prune_all;
        match engine
            .prune_images(prune_all, Some(&config.docker_prune_until))
            .await
        {
            Ok(space_reclaimed) => info!(space_reclaimed, "unused Docker images pruned"),
            Err(error) => warn!(%error, "Docker image pruning failed"),
        }
    }

    run_compose_updates(config, notifier).await;
    run_system_update(config).await;

    info!(
        checked = checked_count,
        updated = updated_count,
        unchanged = unchanged_count,
        skipped = skipped_count,
        failed = failed_count,
        "update cycle completed"
    );

    if config.update_self && !config.dry_run && !config.docker_monitor_only {
        if let Some(self_container) = evaluated.self_container {
            match engine
                .schedule_self_update(
                    &self_container,
                    config.docker_stop_timeout,
                    config.docker_healthcheck_timeout,
                )
                .await
            {
                Ok(true) => {
                    info!(container = %self_container.name, "self-update helper started; exiting daemon to hand off replacement");
                    return true;
                }
                Ok(false) => {
                    info!(container = %self_container.name, "systower image unchanged; no self-update needed");
                }
                Err(error) => {
                    warn!(container = %self_container.name, %error, "self-update failed");
                }
            }
        }
    }

    false
}

/// Compose is an independent opt-in update path: it only uses configured source
/// projects and selected services, and does not reconstruct containers manually.
async fn run_compose_updates(config: &Config, notifier: Option<&Notifier>) {
    if !config.compose_enabled {
        return;
    }
    let targets = match config.compose_targets() {
        Ok(targets) => targets,
        Err(error) => {
            error!(%error, "invalid scheduled Compose target configuration");
            return;
        }
    };
    for target in targets {
        let service_names = target.services.join(", ");
        let plan = match ComposePlan::new(target.files, target.project_directory, target.services) {
            Ok(plan) => plan,
            Err(error) => {
                warn!(services = %service_names, %error, "Compose target preflight failed");
                continue;
            }
        };
        if config.dry_run || config.docker_monitor_only {
            info!(services = %service_names, "Compose target eligible; dry run did not check remote images");
            continue;
        }

        let result = tokio::task::spawn_blocking(move || compose::execute(&plan, true)).await;
        let event = match result {
            Ok(Ok(())) => {
                info!(services = %service_names, "Compose update commands completed");
                NotificationEvent {
                    event: "compose.checked".into(),
                    title: format!("Compose command completed: {service_names}"),
                    message: "Compose pull/up completed; application-level health is not verified"
                        .into(),
                }
            }
            Ok(Err(error)) => {
                warn!(services = %service_names, %error, "Compose update command failed");
                NotificationEvent {
                    event: "compose.failure".into(),
                    title: format!("Compose command failed: {service_names}"),
                    message: error.to_string(),
                }
            }
            Err(error) => {
                warn!(services = %service_names, %error, "Compose update worker failed");
                NotificationEvent {
                    event: "compose.failure".into(),
                    title: format!("Compose worker failed: {service_names}"),
                    message: error.to_string(),
                }
            }
        };
        if let Some(notifier) = notifier {
            if let Err(error) = notifier.send(&event).await {
                warn!(%error, "Compose notification delivery failed");
            }
        }
    }
}

async fn run_system_update(config: &Config) {
    if config.system_enabled {
        if config.dry_run || config.docker_monitor_only {
            info!("host package update planned (dry run)");
            return;
        }
        let result = crate::host::read_host_os_release()
            .and_then(|contents| crate::host::plan(&contents))
            .map(|mut plan| {
                if config.system_full_upgrade
                    && matches!(
                        plan.distribution,
                        crate::host::Distribution::Debian | crate::host::Distribution::Ubuntu
                    )
                {
                    plan.full_upgrade = true;
                    if let Some(command) = plan.command.get_mut(4) {
                        *command = "full-upgrade".into();
                    }
                }
                plan
            })
            .and_then(|plan| crate::host::apply(&plan, true).map(|_| plan));
        if config.rpi_network_immunity {
            if let Err(error) = crate::host::apply_network_immunity(true) {
                warn!(%error, "Raspberry Pi network immunity setup failed");
            }
        }
        match result {
            Ok(plan) if config.system_reboot && crate::host::reboot_required(&plan) => {
                if let Err(error) = crate::host::reboot(true) {
                    warn!(%error, "host reboot failed");
                }
            }
            Ok(_) => info!("host package update completed"),
            Err(error) => warn!(%error, "host package update failed"),
        }
    }
}
