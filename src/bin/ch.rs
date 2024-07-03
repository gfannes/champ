use champetter::{cli, config, util};

fn main() -> util::Result<()> {
    let mut app = cli::App::try_new(config::CliArgs::parse())?;

    app.run()?;

    Ok(())
}
