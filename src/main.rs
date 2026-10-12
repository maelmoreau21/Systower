use clap::Parser;
use systower::cli::{ConfigCommand, DockerCommand, SystemCommand};
use systower::{
    cli::{Cli, Command},
    config::Config,
    daemon,
    docker::{DockerEngine, UpdateOptions},
    host,
    state::{InstanceLock, StateJournal},
    update::HealthPolicy,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let config = Config::from_env()?;

    tracing_subscriber::fmt()
        .with_env_filter(config.log_level.clone())
        .with_target(false)
        .init();

    match cli.command.unwrap_or(Command::Status) {
        Command::Run => daemon::run(config).await?,
        Command::Status => {
            println!("Systower {}", env!("CARGO_PKG_VERSION"));
            println!("configuration: valid");
        }
        Command::Check => {
            config.validate()?;
            println!("configuration: valid");
        }
        Command::Docker(args) => match args.command {
            DockerCommand::Check => {
                let engine = DockerEngine::connect().await?;
                let containers = engine.list_allowed(&config.policy()).await?;
                println!("docker: reachable");
                println!("allowed containers: {}", containers.len());
            }
            DockerCommand::InspectConfig { container, image } => {
                let engine = DockerEngine::connect().await?;
                let definition = engine.recreation_config(&container, image).await?;
                println!("{}", serde_json::to_string_pretty(&definition.config)?);
            }
            DockerCommand::Pull { image } => {
                let engine = DockerEngine::connect().await?;
                let image_id = engine.pull_image(&image).await?;
                println!("image: {image}");
                println!("identity: {image_id}");
            }
            DockerCommand::Update {
                container,
                image,
                health_timeout,
                allow_no_healthcheck,
                no_pull,
            } => {
                let _lock = InstanceLock::acquire(format!("{}.lock", config.state_file))?;
                let journal = StateJournal::open(&config.state_file)?;
                let engine = DockerEngine::connect().await?;
                let result = engine
                    .update_container(
                        &container,
                        &image,
                        &journal,
                        UpdateOptions {
                            health_policy: HealthPolicy {
                                allow_no_healthcheck,
                                stability_seconds: 5,
                            },
                            stop_timeout: config.docker_stop_timeout,
                            health_timeout,
                            pull: !no_pull,
                            cleanup_old_image: config.docker_cleanup,
                        },
                    )
                    .await?;
                println!("updated: {}", result.container_name);
                println!("state: {:?}", result.state);
            }
        },
        Command::System(args) => match args.command {
            SystemCommand::Check => {
                let contents = std::fs::read_to_string("/proc/1/root/etc/os-release")
                    .or_else(|_| std::fs::read_to_string("/etc/os-release"))?;
                let plan = host::plan(&contents)?;
                println!("distribution: {:?}", plan.distribution);
                println!("package command: {}", plan.command.join(" "));
            }
            SystemCommand::Update { dry_run } => {
                let contents = std::fs::read_to_string("/proc/1/root/etc/os-release")
                    .or_else(|_| std::fs::read_to_string("/etc/os-release"))?;
                let plan = host::plan(&contents)?;
                println!("distribution: {:?}", plan.distribution);
                println!("planned command: {}", plan.command.join(" "));
                if !dry_run {
                    host::apply(&plan, true)?;
                    if config.system_reboot && host::reboot_required(&plan) {
                        host::reboot(true)?;
                    }
                }
            }
        },
        Command::Config(args) => match args.command {
            ConfigCommand::Validate => {
                config.validate()?;
                println!("configuration: valid");
            }
        },
        Command::Version => println!("{}", env!("CARGO_PKG_VERSION")),
    }

    Ok(())
}
