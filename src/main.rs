use champ::{cli, config, util};
use tracing::trace;
use tracing_subscriber::EnvFilter;

fn main() -> util::Result<()> {
    let cli_args = config::CliArgs::try_parse()?;

    let default_level = match cli_args.verbose {
        0 => "error",
        1 => "warn",
        2 => "info",
        _ => "trace",
    };
    let filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default_level));
    tracing_subscriber::fmt().with_env_filter(filter).init();

    trace!("cli_args: {:?}", &cli_args);

    let mut app = cli::App::try_new(cli_args)?;

    app.run()?;

    Ok(())
}
