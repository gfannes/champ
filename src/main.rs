mod config;
mod ctrl;
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

    let mut path_data = data::Path::from(std::env::current_dir()?);

    let mut commander = ctrl::Commander::new();

    'mainloop: loop {
        while let Some(event) = tui.event()? {
            commander.process(event)?;
        }

        for command in commander.commands() {
            match command {
                ctrl::Command::Quit => break 'mainloop,
                ctrl::Command::In => {
                    path_data.parts.pop();
                }
                _ => {}
            }
        }

        tui.clear();

        tui.move_to(0, 0)?;
        let mut region = tui.region()?;
        let mut path_tui = tui::Path::new(region);
        path_tui.draw(&mut tui, &path_data)?;

        tui.flush()?;
    }

    Ok(())
}
