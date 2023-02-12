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
    let mut status = data::status::Line::new();

    let mut commander = ctrl::Commander::new();

    let mut location_list = data::List::new();
    let mut parent_list = data::List::new();
    let mut preview_list = data::List::new();

    let mut folder_filter = data::Filter {
        hidden: false,
        sort: true,
    };
    let file_filter = data::Filter {
        hidden: true,
        sort: false,
    };

    let mut count: usize = 0;
    'mainloop: loop {
        term.process_events(settings.mainloop_timeout_ms, |event| {
            commander.process(event)
        })?;

        let mut new_location_path = path_mgr.location().clone();
        for command in commander.commands() {
            match command {
                ctrl::Command::Quit => break 'mainloop,

                ctrl::Command::In => {
                    if let Some(name) = new_location_path.pop() {
                        status_line = format!("name: {:?}", name);
                        status.add_timed_message(format!("name: {:?}", name), 500);
                        let index = indices.goc(&new_location_path);
                        index.name = Some(name);
                    }
                }
                ctrl::Command::Up => {
                    let index = indices.goc(&new_location_path);
                    index.ix -= 1;
                    index.name = None;
                }
                ctrl::Command::Down => {
                    let index = indices.goc(&new_location_path);
                    index.ix += 1;
                    index.name = None;
                }
                ctrl::Command::Out => {
                    let index = indices.goc(&new_location_path);
                    if let Some(name) = &index.name {
                        new_location_path.push(name);
                    }
                }
                ctrl::Command::SwitchTab(tab) => {
                    path_mgr.switch_tab(tab)?;
                    new_location_path = path_mgr.location().clone();
                }
                _ => {}
            }
        }

        if tree.is_file(&new_location_path) {
            process::Command::new("hx")
                .arg(std::path::PathBuf::from(&new_location_path))
                .status()?;
        } else {
            match tree.read_folder(&new_location_path) {
                Ok(nodes) => {
                    location_list.set_items(&nodes, &folder_filter);
                    path_mgr.set_location(new_location_path);
                }
                Err(error) => {
                    status_line = format!("Error: {}", error);
                    status.add_timed_message(format!("Error: {}", error), 500);
                }
            }
        }

        location_list.update_focus(indices.goc(path_mgr.location()));

        {
            let parent_path = path_mgr.parent();
            match tree.read_folder(&parent_path) {
                Ok(nodes) => {
                    parent_list.set_items(&nodes, &folder_filter);
                }
                Err(error) => {
                    status_line = format!("Error: {}", error);
                    status.add_timed_message(format!("Error: {}", error), 500);
                }
            }
            parent_list.update_focus(indices.goc(&parent_path));
        }

        {
            let mut preview_path = path_mgr.location().clone();
            if let Some(name) = &indices.goc(&preview_path).name {
                preview_path.push(name);

                if tree.is_file(&preview_path) {
                    match tree.read_file(&preview_path) {
                        Ok(nodes) => {
                            preview_list.set_items(&nodes, &file_filter);
                        }
                        Err(error) => {
                            status_line = format!("Error: {}", error);
                            status.add_timed_message(format!("Error: {}", error), 500);
                        }
                    }
                } else {
                    match tree.read_folder(&preview_path) {
                        Ok(nodes) => {
                            preview_list.set_items(&nodes, &folder_filter);
                        }
                        Err(error) => {
                            status_line = format!("Error: {}", error);
                            status.add_timed_message(format!("Error: {}", error), 500);
                        }
                    }
                }
                preview_list.update_focus(indices.goc(&preview_path));
            }
        }

        // Make sure that the complete layout is redrawn. Performing a term.clear()? results in flicker

        let layout = tui::Layout::create(&term)?;

        tui::Text::new(layout.path).draw(
            &mut term,
            format!("[{}]: {}", path_mgr.tab, path_mgr.location()),
        )?;

        tui::List::new(layout.location).draw(&mut term, &location_list)?;
        tui::List::new(layout.parent).draw(&mut term, &parent_list)?;
        tui::List::new(layout.preview).draw(&mut term, &preview_list)?;

        tui::Text::new(layout.status).draw(&mut term, &status_line)?;
        tui::status::Line::new(layout.status).draw(&mut term, &status)?;

        term.flush()?;

        count += 1;
    }

    Ok(())
}
