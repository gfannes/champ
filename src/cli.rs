use crate::{amp, config, fail, path, util};

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
                    self.list_files_recursive_(&path::Path::root())?;
                }
            }
        }
        Ok(())
    }

    fn list_files_recursive_(&mut self, parent: &path::Path) -> util::Result<()> {
        match parent.fs_path()? {
            path::FsPath::Folder(folder) => {
                for child in self.tree.list(parent)? {
                    self.list_files_recursive_(&child)?;
                }
            }
            path::FsPath::File(file) => {
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
            let mut root_expanded = std::path::PathBuf::new();
            let mut first = true;
            for component in root_pb.components() {
                println!("component: {:?}", &component);
                match component {
                    std::path::Component::Prefix(prefix) => {
                        root_expanded.push(prefix.as_os_str());
                        first = false;
                    }
                    std::path::Component::RootDir => {
                        root_expanded.push("/");
                        first = false;
                    }
                    std::path::Component::CurDir => {
                        if first {
                            root_expanded.push(std::env::current_dir()?);
                            first = false;
                        }
                    }
                    std::path::Component::Normal(normal) => {
                        if first {
                            root_expanded.push(std::env::current_dir()?);
                            first = false;
                        }
                        root_expanded.push(normal);
                    }
                    std::path::Component::ParentDir => {
                        fail!("No support for '..' in root dir yet");
                    }
                }
            }
            println!("root_expanded: {:?}", &root_expanded);
            tree_opt = Some(config::Tree {
                name: "<root>".into(),
                path: root_expanded,
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
