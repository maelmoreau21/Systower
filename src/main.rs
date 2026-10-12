use clap::Parser;
use systower::cli::ConfigCommand;
use systower::{
    cli::{Cli, Command},
    config::Config,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
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
