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

    let mut path = data::Path::from(std::env::current_dir()?);

    let mut status_line = "Status line".to_string();

    let mut commander = ctrl::Commander::new();

    'mainloop: loop {
        while let Some(event) = tui.event()? {
            commander.process(event)?;
        }

        for command in commander.commands() {
            match command {
                ctrl::Command::Quit => break 'mainloop,
                ctrl::Command::In => {
                    path.parts.pop();
                }
                _ => {}
            }
        }

        tui.clear();

        let mut region = tui.region()?;

        {
            let mut text = tui::Text::new(
                region
                    .pop_line(tui::Side::Top)
                    .ok_or(my::Error::create("Cannot pop line for Path"))?,
            );
            text.draw(&mut tui, format!("{}", &path))?;
        }
        {
            let mut text = tui::Text::new(
                region
                    .pop_line(tui::Side::Bottom)
                    .ok_or(my::Error::create("Cannot pop line for Status"))?,
            );
            text.draw(&mut tui, &status_line)?;
        }

        tui.flush()?;
    }

    Ok(())
}
