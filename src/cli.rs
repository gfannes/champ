use crate::{amp, config, fail, util};

pub struct App {
    config: Config,
    tree: amp::Tree,
}

impl App {
    pub fn try_new(cli_args: config::CliArgs) -> util::Result<App> {
        let config = Config::load(cli_args)?;

        let app = App {
            config,
            tree: amp::Tree::new(),
        };
        Ok(app)
    }

    pub fn run(&mut self) -> util::Result<()> {
        if let Some(filter) = &self.config.filter {
            self.tree.set_filter(filter.into());
        }

        if let Some(command) = self.config.command.as_ref() {
            match command {
                config::Command::Config { verbose } => {
                    println!("config: {:?}", self.config);
                }
                config::Command::List { verbose } => {
                    self.list_files_recursive_(&amp::Path::root())?;
                }
            }
        }
        Ok(())
    }

    fn list_files_recursive_(&mut self, parent: &amp::Path) -> util::Result<()> {
        let fs_path = parent.fs_path()?;
        match parent.fs_path()? {
            amp::FsPath::Folder(folder) => {
                for child in self.tree.list(parent)? {
                    self.list_files_recursive_(&child)?;
                }
            }
            amp::FsPath::File(file) => {
                // println!("{}", file.display());
            }
        }
        Ok(())
    }
}

#[derive(Debug)]
struct Config {
    global: config::Global,
    command: Option<config::Command>,
    filter: Option<config::Filter>,
}

impl Config {
    fn load(cli_args: config::CliArgs) -> util::Result<Config> {
        let global = config::Global::load(&cli_args)?;

        let mut filter_opt = None;
        if let Some(filter_str) = &cli_args.filter {
            for filter in &global.filter {
                if &filter.name == filter_str {
                    filter_opt = Some(filter.clone());
                }
            }
            match &filter_opt {
                Some(filter) => {
                    println!("Using filter {:?}", filter);
                }
                None => {
                    fail!("Unknown filter '{}'", filter_str);
                }
            }
        }

        let mut config = Config {
            global,
            command: cli_args.command,
            filter: filter_opt,
        };

        Ok(config)
    }
}
