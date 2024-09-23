use crate::{config, fail, fs, lex, path, tree, util};
use std::io;

pub struct App {
    config: Config,
    amp_forest: fs::Forest,
    buffer: Vec<u8>,
    size: usize,
    forest: tree::Forest,
}

impl App {
    pub fn try_new(cli_args: config::CliArgs) -> util::Result<App> {
        let config = Config::load(cli_args)?;

        let app = App {
            config,
            amp_forest: fs::Forest::new(),
            buffer: Vec::new(),
            size: 0,
            forest: Default::default(),
        };
        Ok(app)
    }

    pub fn run(&mut self) -> util::Result<()> {
        if let Some(forest) = &self.config.forest {
            self.amp_forest.set_forest(forest.into());
        }

        if let Some(command) = self.config.command.as_ref() {
            match command {
                config::Command::Config { verbose } => {
                    println!("config: {:?}", self.config);
                }
                config::Command::List { verbose } => {
                    self.list_files_recursive_(&path::Path::root())?;
                }
                config::Command::Search { verbose, needle } => {
                    let needle = format!("@{}", needle);

                    self.add_to_forest_recursive_(&path::Path::root(), 0)?;

                    let mut cur_filename = None;
                    self.forest.dfs(|tree, node| {
                        if let Some(filename) = &tree.filename {
                            println!(
                                "filename {} {}",
                                filename.display(),
                                node.get_main(&tree.content)
                            );
                        }
                        let main = node.get_main(&tree.content);
                        // For Markdown, we allow a match anywhere, for SourceCode, we only allow a match at the front
                        let is_match = match tree.format {
                            tree::Format::SourceCode { comment: _ } => {
                                !main.starts_with("&&") && main.starts_with(&needle)
                            }
                            _ => main.contains(&needle),
                        };
                        if is_match {
                            // println!(
                            //     "starts_with: {} needle: {}, main: {}",
                            //     main.starts_with(&needle),
                            //     &needle,
                            //     &main
                            // );
                            if true && cur_filename != tree.filename {
                                cur_filename = tree.filename.clone();
                                if let Some(fp) = &cur_filename {
                                    println!("{}", fp.display());
                                } else {
                                    println!("<Unknown filename>");
                                }
                            }
                            node.print(&tree.content, &tree.format);
                        }
                    });
                }
            }
        }

        println!("Total size: {}", self.size);

        Ok(())
    }

    fn list_files_recursive_(&mut self, parent: &path::Path) -> util::Result<()> {
        match parent.fs_path()? {
            path::FsPath::Folder(folder) => {
                for child in self.amp_forest.list(parent)? {
                    self.list_files_recursive_(&child)?;
                }
            }
            path::FsPath::File(fp) => {
                let mut file = std::fs::File::open(&fp)?;

                let do_process = self.amp_forest.max_size().map_or(true, |max_size| {
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

    fn add_to_forest_recursive_(
        &mut self,
        parent: &path::Path,
        level: u64,
    ) -> util::Result<Option<usize>> {
        let tree_ix = match parent.fs_path()? {
            path::FsPath::Folder(folder) => {
                let mut tree = tree::Tree::folder(&folder);
                for child in self.amp_forest.list(parent)? {
                    if let Some(tree_ix) = self.add_to_forest_recursive_(&child, level + 1)? {
                        tree.root().links.push(tree_ix);

                        let ix = tree.nodes.len();
                        let mut node = tree::Node::default();

                        node.prefix.start = tree.content.len();
                        node.prefix.end = tree.content.len();
                        tree.content
                            .push_str(&format!("{}", child.path_buf().display()));
                        node.postfix.start = tree.content.len();
                        node.postfix.end = tree.content.len();

                        tree.nodes.push(node);
                    }
                }
                Some(self.forest.add(tree, level)?)
            }
            path::FsPath::File(fp) => match tree::Tree::from_path(&fp) {
                Err(err) => {
                    eprintln!(
                        "Could not create tree.Tree from '{}': {}",
                        fp.display(),
                        err
                    );
                    None
                }
                Ok(tree) => Some(self.forest.add(tree, level)?),
            },
        };
        Ok(tree_ix)
    }
}

#[derive(Debug)]
struct Config {
    global: config::Global,
    command: Option<config::Command>,
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

        let config = Config {
            global,
            command: cli_args.command,
            forest: forest_opt,
        };

        Ok(config)
    }
}
