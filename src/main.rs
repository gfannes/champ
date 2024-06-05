use champetter::{app, cli, util};

fn main() -> util::Result<()> {
    let mut app = app::App::create(&cli::Options::parse_from_cli())?;

    app.run()?;

    Ok(())
}
