use clap::{Args, Parser, Subcommand};
use std::path::PathBuf;

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
    Compose(ComposeArgs),
    System(SystemArgs),
    Config(ConfigArgs),
    Version,
}

#[derive(Debug, Args)]
pub struct ComposeArgs {
    #[command(subcommand)]
    pub command: ComposeCommand,
}

#[derive(Debug, Subcommand)]
pub enum ComposeCommand {
    Update {
        /// Explicit Compose files; paths are resolved before execution.
        #[arg(short = 'f', long = "file", required = true)]
        files: Vec<PathBuf>,
        /// The original Compose working directory containing .env and other files.
        #[arg(long)]
        project_directory: Option<PathBuf>,
        /// Only explicitly selected services may be updated.
        #[arg(long = "service", required = true)]
        services: Vec<String>,
        /// Explicitly run docker compose; without this flag only preview the plan.
        #[arg(long)]
        apply: bool,
    },
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
