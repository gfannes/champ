mod config;
mod data;
#[macro_use]
mod my;
mod show;
mod tui;

fn main() -> my::Result<()> {
    let cli_options = config::cli::Options::parse()?;

    let settings = config::Settings::load(&cli_options)?;

    let mut tui = tui::Tui::new()?;

    let tree = data::Tree::new();

    let path = data::Path::from(std::env::current_dir()?);

    loop {
        match tui.event() {
            _ => {
                break;
            }
        }
    }

    Ok(())
}
