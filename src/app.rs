use crate::{cli, config, ctrl, data, tui, util};

use dirs;
use flexi_logger;
use log;
use std::{env, ffi, process};

pub struct App {
    settings: config::Settings,
    _logger_handle: flexi_logger::LoggerHandle,

    term: tui::Term,
    commander: ctrl::Commander,

    tree: data::Tree,
    indices: data::Indices,
    path_mgr: data::path::Mgr,
    status_line: data::status::Line,
    location_list: data::List,
    parent_list: data::List,
    preview_list: data::List,
    folder_filter: data::Filter,
    file_filter: data::Filter,
}

impl App {
    pub fn create(cli_options: &cli::Options) -> util::Result<App> {
        let settings = config::Settings::load(&cli_options)?;

        let logger_handle = flexi_logger::Logger::try_with_str(&settings.log_level)?
            .log_to_file(
                flexi_logger::FileSpec::default()
                    .o_directory(dirs::cache_dir().map(|d| d.join("champ"))),
            )
            .start()?;
        log::info!("Starting champ");

        let app = App {
            settings,
            _logger_handle: logger_handle,
            term: tui::Term::new()?,
            commander: ctrl::Commander::new(),
            tree: data::Tree::new(),
            indices: data::Indices::new(),
            path_mgr: data::path::Mgr::new()?,
            status_line: data::status::Line::new(),
            location_list: data::List::new(),
            parent_list: data::List::new(),
            preview_list: data::List::new(),
            folder_filter: data::Filter {
                hidden: false,
                sort: true,
                filter: String::new(),
            },
            file_filter: data::Filter {
                hidden: true,
                sort: false,
                filter: String::new(),
            },
        };

        Ok(app)
    }

    pub fn run(&mut self) -> util::Result<()> {
        'mainloop: loop {
            self.term
                .process_events(self.settings.mainloop_timeout_ms, |event| {
                    self.commander.process(event)
                })?;

            let mut new_location_path = self.path_mgr.location().clone();
            for command in self.commander.commands() {
                match command {
                    ctrl::Command::Quit => break 'mainloop,

                    ctrl::Command::In => {
                        if let Some(name) = new_location_path.pop() {
                            self.status_line
                                .set_timed_message(format!("name: {:?}", name), 500);
                            let index = self.indices.goc(&new_location_path);
                            index.name = Some(name);
                            self.commander.str.clear();
                        }
                    }
                    ctrl::Command::Out => {
                        let index = self.indices.goc(&new_location_path);
                        if let Some(name) = &index.name {
                            new_location_path.push(name);
                            self.commander.str.clear();
                        }
                    }
                    ctrl::Command::Up => {
                        let index = self.indices.goc(&new_location_path);
                        index.ix -= 1;
                        index.name = None;
                    }
                    ctrl::Command::Down => {
                        let index = self.indices.goc(&new_location_path);
                        index.ix += 1;
                        index.name = None;
                    }
                    ctrl::Command::UpUp => {
                        let index = self.indices.goc(&new_location_path);
                        index.ix -= 10;
                        index.name = None;
                    }
                    ctrl::Command::DownDown => {
                        let index = self.indices.goc(&new_location_path);
                        index.ix += 10;
                        index.name = None;
                    }
                    ctrl::Command::Top => {
                        let index = self.indices.goc(&new_location_path);
                        index.ix = 0;
                        index.name = None;
                    }
                    ctrl::Command::Bottom => {
                        let index = self.indices.goc(&new_location_path);
                        index.ix = i64::MAX;
                        index.name = None;
                    }

                    ctrl::Command::Shell => {
                        self.term.disable()?;
                        let cwd = env::current_dir()?;
                        let my_path: std::path::PathBuf = self.path_mgr.location().into();
                        env::set_current_dir(my_path)?;
                        process::Command::new(
                            std::env::var_os("SHELL")
                                .unwrap_or(ffi::OsStr::new("/bin/zsh").to_os_string()),
                        )
                        .status()?;
                        env::set_current_dir(cwd)?;
                        self.term.enable()?;
                    }

                    ctrl::Command::Delete => {
                        let path = std::path::PathBuf::from(&new_location_path);
                        self.status_line
                            .set_timed_message(format!("Deleting {:?}", &path), 500);
                    }

                    ctrl::Command::SwitchTab(tab) => {
                        self.path_mgr.switch_tab(tab)?;
                        new_location_path = self.path_mgr.location().clone();
                        self.commander.str.clear();
                    }
                    ctrl::Command::SwitchMode(mode) => {
                        self.status_line.mode = mode;
                        self.commander.str.clear();
                    }
                }
            }

            self.status_line.message = self.commander.str.clone();
            self.folder_filter.filter = self.commander.str.clone();

            if self.tree.is_file(&new_location_path) {
                let path = std::path::PathBuf::from(&new_location_path);
                let app = match path.extension() {
                    Some(ext) => {
                        if ext == ffi::OsStr::new("pdf") {
                            "evince"
                        } else if ext == ffi::OsStr::new("zip") {
                            "unzip"
                        } else if ext == ffi::OsStr::new("graphml") {
                            "yed"
                        } else {
                            "hx"
                        }
                    }
                    None => "hx",
                };
                self.term.disable()?;
                let cwd = env::current_dir()?;
                let my_path: std::path::PathBuf = self.path_mgr.location().into();
                env::set_current_dir(my_path)?;
                if let Err(err) = process::Command::new(app).arg(path).status() {
                    self.status_line.set_timed_message(
                        format!("Error: Could not run '{}': {}", app, err),
                        2000,
                    );
                }
                env::set_current_dir(cwd)?;
                self.term.enable()?;
            } else {
                match self.tree.read_folder(&new_location_path) {
                    Ok(nodes) => {
                        self.location_list.set_items(&nodes, &self.folder_filter);
                        self.path_mgr.set_location(new_location_path);
                    }
                    Err(error) => {
                        self.status_line
                            .set_timed_message(format!("Error: {}", error), 500);
                    }
                }
            }

            self.location_list
                .update_focus(self.indices.goc(self.path_mgr.location()));

            {
                let parent_path = self.path_mgr.parent();
                match self.tree.read_folder(&parent_path) {
                    Ok(nodes) => {
                        self.parent_list.set_items(&nodes, &self.folder_filter);
                    }
                    Err(error) => {
                        self.status_line
                            .set_timed_message(format!("Error: {}", error), 500);
                    }
                }
                self.parent_list
                    .update_focus(self.indices.goc(&parent_path));
            }

            {
                let mut preview_path = self.path_mgr.location().clone();
                if let Some(name) = &self.indices.goc(&preview_path).name {
                    preview_path.push(name);

                    if self.tree.is_file(&preview_path) {
                        match self.tree.read_file(&preview_path) {
                            Ok(nodes) => {
                                self.preview_list.set_items(&nodes, &self.file_filter);
                            }
                            Err(error) => {
                                self.status_line
                                    .set_timed_message(format!("Error: {}", error), 500);
                            }
                        }
                    } else {
                        match self.tree.read_folder(&preview_path) {
                            Ok(nodes) => {
                                self.preview_list.set_items(&nodes, &self.folder_filter);
                            }
                            Err(error) => {
                                self.status_line
                                    .set_timed_message(format!("Error: {}", error), 500);
                            }
                        }
                    }
                    self.preview_list
                        .update_focus(self.indices.goc(&preview_path));
                }
            }

            // Make sure that the complete layout is redrawn. Performing a term.clear()? results in flicker

            let is_filter_mode = matches!(self.status_line.mode, ctrl::Mode::Filter);

            let layout = tui::Layout::create(&self.term)?;

            tui::Text::new(layout.path).set_mark(is_filter_mode).draw(
                &mut self.term,
                format!("[{}]: {}", self.path_mgr.tab, self.path_mgr.location()),
            )?;

            tui::List::new(layout.location).draw(&mut self.term, &self.location_list)?;
            tui::List::new(layout.parent).draw(&mut self.term, &self.parent_list)?;
            tui::List::new(layout.preview).draw(&mut self.term, &self.preview_list)?;

            tui::Text::new(layout.status)
                .set_mark(is_filter_mode)
                .draw(&mut self.term, self.status_line.message())?;

            tui::status::Line::new(layout.status).draw(&mut self.term, &self.status_line)?;

            self.term.flush()?;
        }

        log::info!("Stopping App.run()");

        Ok(())
    }
}
