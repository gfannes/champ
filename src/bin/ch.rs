use champetter::{cli, config, util};

fn main() -> util::Result<()> {
    tracing_subscriber::fmt::init();

    let mut app = cli::App::try_new(config::CliArgs::try_parse()?)?;

    app.run()?;

    Ok(())
}
