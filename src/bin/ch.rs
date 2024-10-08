use champetter::{cli, config, util};
use tracing_subscriber::EnvFilter;

fn main() -> util::Result<()> {
    let default_level = "warn";
    let filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default_level));
    tracing_subscriber::fmt().with_env_filter(filter).init();

    let mut app = cli::App::try_new(config::CliArgs::try_parse()?)?;

    app.run()?;

    Ok(())
}
