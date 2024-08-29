use crate::{amp, config, fail, lex, path, util};
use std::{fs, io};

pub struct App {
    config: Config,
    tree: amp::Tree,
    buffer: Vec<u8>,
    size: usize,
}

impl App {
    pub fn try_new(cli_args: config::CliArgs) -> util::Result<App> {
        let config = Config::load(cli_args)?;

        let app = App {
            config,
            tree: amp::Tree::new(),
            buffer: Vec::new(),
            size: 0,
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

        println!("Total size: {}", self.size);

        Ok(())
    }

    fn list_files_recursive_(&mut self, parent: &path::Path) -> util::Result<()> {
        match parent.fs_path()? {
            path::FsPath::Folder(folder) => {
                for child in self.tree.list(parent)? {
                    self.list_files_recursive_(&child)?;
                }
            }
            path::FsPath::File(fp) => {
                let mut file = fs::File::open(&fp)?;

                let do_process = self.tree.max_size().map_or(true, |max_size| {
                    // Do not process large files
                    file.metadata()
                        .map_or(false, |md| md.len() <= max_size as u64)
                });

                if do_process {
                    self.buffer.clear();
                    let size = io::Read::read_to_end(&mut file, &mut self.buffer)?;
                    self.size += size;
                    println!("{}\t{}", size, fp.display());
                    match std::str::from_utf8(&self.buffer) {
                        Err(_) => eprintln!("Could not convert '{}' to UTF8", fp.display()),
                        Ok(content) => {
                            let mut lexer = lex::Lexer::new(content);
                            let tokens = lexer.tokenize();
                            for token in tokens.iter().take(0) {
                                token.print("\t", content);
                            }
                        }
                    }
                }
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
                include: Vec::new(),
                max_size: None,
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
