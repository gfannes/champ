use crate::{amp, config, fail, fs, path, tree, util};

pub struct App {
    config: Config,
    fs_forest: fs::Forest,
    builder: tree::builder::Builder,
}

impl App {
    pub fn try_new(cli_args: config::CliArgs) -> util::Result<App> {
        let config = Config::load(cli_args)?;

        let app = App {
            config,
            fs_forest: fs::Forest::new(),
            builder: tree::builder::Builder::new(),
        };
        Ok(app)
    }

    pub fn run(&mut self) -> util::Result<()> {
        if let Some(forest) = &self.config.forest {
            self.fs_forest.set_forest(forest.into());
        }

        // Using &self.config.command complicates using &mut self later.
        // Copyng the command once does not impact performance.
        match self.config.command {
            Command::Config => {
                println!("config: {:?}", self.config);
            }
            Command::List => {
                self.list_files_recursive_(&path::Path::root())?;
            }
            Command::Search => {
                let needle = self.config.args.get(0).map(|s| s.clone());
                println!("needle: {:?}", &needle);

                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;
            }
            Command::None => {}
            Command::Query => {
                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;
                forest.dfs(|tree, node| {
                    let has = |v: &Vec<amp::Metadata>, n: &str| {
                        v.iter().filter(|md| &md.kv.0 == n).next().is_some()
                    };

                    let mut do_print;
                    if let Some((needle, constraints)) = self.config.args.split_first() {
                        do_print = has(&node.org, needle);
                        for constraint in constraints {
                            if !has(&node.agg, constraint) {
                                do_print = false;
                            }
                        }
                    } else {
                        do_print = !node.org.is_empty();
                    }

                    if do_print {
                        if let Some(filename) = &tree.filename {
                            println!("{}:{}", filename.display(), node.line_nr.unwrap_or(0));
                        }
                        for md in &node.org {
                            println!("\t{:?}", &md.kv.0);
                        }
                    }
                });
            }
        }

        Ok(())
    }

    fn list_files_recursive_(&mut self, parent: &path::Path) -> util::Result<()> {
        match parent.fs_path()? {
            path::FsPath::Folder(_folder) => {
                for child in self.fs_forest.list(parent)? {
                    self.list_files_recursive_(&child)?;
                }
            }
            path::FsPath::File(fp) => {
                println!("{}", fp.display());
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
enum Command {
    None,
    Config,
    Query,
    Search,
    List,
}

#[derive(Debug, Clone)]
struct Config {
    global: config::Global,
    command: Command,
    args: Vec<String>,
    forest: Option<config::Forest>,
}

impl Config {
    fn load(cli_args: config::CliArgs) -> util::Result<Config> {
        let global = config::Global::load(&cli_args)?;

        let mut forest_opt = None;
        if let Some(forest_str) = &cli_args.forest {
            for forest in &global.forest {
                if &forest.name == forest_str {
                    forest_opt = Some(forest.clone());
                }
            }
            match &forest_opt {
                Some(forest) => {
                    println!("Using forest {:?}", forest);
                }
                None => {
                    fail!("Unknown forest '{}'", forest_str);
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
            forest_opt = Some(config::Forest {
                name: "<root>".into(),
                path: root_expanded,
                hidden: !cli_args.hidden,
                ignore: !cli_args.ignored,
                include: Vec::new(),
                max_size: None,
            });
        }

        let command = if cli_args.query {
            Command::Query
        } else if cli_args.search {
            Command::Search
        } else if cli_args.list {
            Command::List
        } else {
            Command::None
        };

        let config = Config {
            global,
            command,
            args: cli_args.rest.clone(),
            forest: forest_opt,
        };

        Ok(config)
    }
}
