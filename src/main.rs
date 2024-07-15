use champetter::{config, tui, util};

fn main() -> util::Result<()> {
    let mut app = tui::App::try_new(&config::CliArgs::try_parse()?)?;

    app.run()?;

    Ok(())
}
