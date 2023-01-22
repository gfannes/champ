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

    let mut term = tui::Term::new()?;

    let tree = data::Tree::new();

    let mut path = data::Path::from(std::env::current_dir()?);
    let mut index = data::Index::new();

    let mut status_line = "Status line".to_string();

    let mut commander = ctrl::Commander::new();

    let mut list = data::List::new();

    let mut filter = data::Filter::new();

    let mut count: usize = 0;
    'mainloop: loop {
        let nodes = tree.nodes(&path)?;

        list.set_items(&nodes, &filter);
        list.update_focus(&mut index);

        for command in commander.commands() {
            match command {
                ctrl::Command::Quit => break 'mainloop,
                ctrl::Command::In => {
                    path.parts.pop();
                }
                ctrl::Command::Up => {
                    index.ix -= 1;
                    index.name = None;
                }
                ctrl::Command::Down => {
                    index.ix += 1;
                    index.name = None;
                }
                _ => {}
            }
        }
        status_line = format!("index: {:?}", index);

        term.clear()?;

        let layout = tui::Layout::create(&term)?;

        tui::Text::new(layout.path).draw(&mut term, format!("{}", &path))?;

        tui::List::new(layout.location).draw(&mut term, &list)?;

        tui::Text::new(layout.status).draw(&mut term, &status_line)?;

        term.flush()?;

        term.process_events(settings.mainloop_timeout_ms, |event| {
            commander.process(event)
        })?;

        count += 1;
    }

    Ok(())
}
