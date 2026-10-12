use clap::{Args, Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(
    name = "systower",
    version,
    about = "Reliable Docker and Linux update daemon"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    Run,
    Status,
    Check,
    Docker(DockerArgs),
    System(SystemArgs),
    Config(ConfigArgs),
    Version,
}

#[derive(Debug, Args)]
pub struct SystemArgs {
    #[command(subcommand)]
    pub command: SystemCommand,
}

#[derive(Debug, Subcommand)]
pub enum SystemCommand {
    Check,
    Update {
        #[arg(long)]
        dry_run: bool,
    },
}

#[derive(Debug, Args)]
pub struct DockerArgs {
    #[command(subcommand)]
    pub command: DockerCommand,
}

#[derive(Debug, Subcommand)]
pub enum DockerCommand {
    Check,
    InspectConfig {
        #[arg(long)]
        container: String,
        #[arg(long)]
        image: String,
    },
    Update {
        #[arg(long)]
        container: String,
        #[arg(long)]
        image: String,
        #[arg(long, default_value_t = 60)]
        health_timeout: u64,
        #[arg(long)]
        allow_no_healthcheck: bool,
        #[arg(long)]
        no_pull: bool,
    },
    Pull {
        #[arg(long)]
        image: String,
    },
}

#[derive(Debug, Args)]
pub struct ConfigArgs {
    #[command(subcommand)]
    pub command: ConfigCommand,
}

#[derive(Debug, Subcommand)]
pub enum ConfigCommand {
    Validate,
}
