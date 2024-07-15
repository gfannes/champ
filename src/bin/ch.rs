use champetter::{cli, config, util};

fn main() -> util::Result<()> {
    let mut app = cli::App::try_new(config::CliArgs::try_parse()?)?;

    app.run()?;

    Ok(())
}
