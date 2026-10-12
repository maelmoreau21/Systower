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
    Status,
    Check,
    Docker(DockerArgs),
    Config(ConfigArgs),
    Version,
}

#[derive(Debug, Args)]
pub struct DockerArgs {
    #[command(subcommand)]
    pub command: DockerCommand,
}

#[derive(Debug, Subcommand)]
pub enum DockerCommand {
    Check,
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
