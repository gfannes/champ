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
        if let Some(tree) = &self.config.tree {
            self.tree.set_tree(tree.into());
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
                println!("{}", file.display());
            }
        }
        Ok(())
    }
}

#[derive(Debug)]
struct Config {
    global: config::Global,
    command: Option<config::Command>,
    tree: Option<config::Tree>,
}

impl Config {
    fn load(cli_args: config::CliArgs) -> util::Result<Config> {
        let global = config::Global::load(&cli_args)?;

        let mut tree_opt = None;
        if let Some(tree_str) = &cli_args.tree {
            for tree in &global.tree {
                if &tree.name == tree_str {
                    tree_opt = Some(tree.clone());
                }
            }
            match &tree_opt {
                Some(tree) => {
                    println!("Using tree {:?}", tree);
                }
                None => {
                    fail!("Unknown tree '{}'", tree_str);
                }
            }
        } else if let Some(root_pb) = &cli_args.root {
            tree_opt = Some(config::Tree {
                name: "<root>".into(),
                path: root_pb.clone(),
                hidden: !cli_args.hidden,
                ignore: !cli_args.ignored,
            });
        }

        let config = Config {
            global,
            command: cli_args.command,
            tree: tree_opt,
        };

        Ok(config)
    }
}
