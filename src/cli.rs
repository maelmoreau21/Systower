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
    Config(ConfigArgs),
    Version,
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
