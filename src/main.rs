use clap::Parser;
use systower::cli::{ConfigCommand, DockerCommand};
use systower::{
    cli::{Cli, Command},
    config::Config,
    docker::DockerEngine,
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
