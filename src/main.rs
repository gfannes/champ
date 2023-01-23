mod config;
mod ctrl;
mod data;
#[macro_use]
mod my;
mod show;
mod tui;

use std::process;

fn main() -> my::Result<()> {
    let cli_options = config::cli::Options::parse()?;

    let settings = config::Settings::load(&cli_options)?;

    let mut term = tui::Term::new()?;

    let tree = data::Tree::new();

    let mut indices = data::Indices::new();

    let mut path_mgr = data::path::Mgr::new()?;

    let mut status_line = "Status line".to_string();

    let mut commander = ctrl::Commander::new();

    let mut list = data::List::new();

    let mut filter = data::Filter::new();

    let mut count: usize = 0;
    'mainloop: loop {
        term.process_events(settings.mainloop_timeout_ms, |event| {
            commander.process(event)
        })?;

        let mut new_path = path_mgr.current().clone();
        for command in commander.commands() {
            match command {
                ctrl::Command::Quit => break 'mainloop,

                ctrl::Command::In => {
                    if let Some(name) = new_path.pop() {
                        status_line = format!("name: {:?}", name);
                        let index = indices.goc(&new_path);
                        index.name = Some(name);
                    }
                }
                ctrl::Command::Up => {
                    let index = indices.goc(&new_path);
                    index.ix -= 1;
                    index.name = None;
                }
                ctrl::Command::Down => {
                    let index = indices.goc(&new_path);
                    index.ix += 1;
                    index.name = None;
                }
                ctrl::Command::Out => {
                    let index = indices.goc(&new_path);
                    if let Some(name) = &index.name {
                        new_path.push(name);
                    }
                }
                ctrl::Command::SwitchTab(tab) => {
                    path_mgr.switch_tab(tab)?;
                    new_path = path_mgr.current().clone();
                }
                _ => {}
            }
        }

        if tree.is_file(&new_path) {
            process::Command::new("hx")
                .arg(std::path::PathBuf::from(&new_path))
                .status()?;
        } else {
            match tree.nodes(&new_path) {
                Ok(nodes) => {
                    list.set_items(&nodes, &filter);
                    path_mgr.set_current(new_path);
                }
                Err(error) => {
                    status_line = format!("Error: {}", error);
                }
            }
        }

        list.update_focus(indices.goc(path_mgr.current()));

        term.clear()?;

        let layout = tui::Layout::create(&term)?;

        tui::Text::new(layout.path).draw(
            &mut term,
            format!("[{}]: {}", path_mgr.current_ix, path_mgr.current()),
        )?;

        tui::List::new(layout.location).draw(&mut term, &list)?;

        tui::Text::new(layout.status).draw(&mut term, &status_line)?;

        term.flush()?;

        count += 1;
    }

    Ok(())
}
