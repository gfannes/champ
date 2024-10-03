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
                let mut filename_lines_s = Vec::<(std::path::PathBuf, Vec<u64>)>::new();

                let needle: Option<amp::KeyValue>;
                let mut constraints = Vec::<amp::KeyValue>::new();
                if let Some((needle_str, constraints_str)) = self.config.args.split_first() {
                    let mut amp_parser = amp::Parser::new();
                    amp_parser.parse(&format!("&{needle_str}"), &amp::Match::OnlyStart);
                    if let Some(stmt) = amp_parser.stmts.first() {
                        match &stmt.kind {
                            amp::Kind::Amp(kv) => needle = Some(kv.clone()),
                            _ => fail!("Expected to find AMP"),
                        }
                    } else {
                        fail!("Expected to find at least one statement");
                    }
                    for constraint_str in constraints_str {
                        amp_parser.parse(&format!("&{constraint_str}"), &amp::Match::OnlyStart);
                        if let Some(stmt) = amp_parser.stmts.first() {
                            match &stmt.kind {
                                amp::Kind::Amp(kv) => constraints.push(kv.clone()),
                                _ => fail!("Expected to find AMP"),
                            }
                        }
                    }
                } else {
                    needle = None;
                }

                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;
                forest.dfs(|tree, node| {
                    let has = |v: &Vec<amp::KeyValue>, n: &amp::KeyValue| {
                        v.iter().filter(|&kv| kv == n).next().is_some()
                    };

                    let mut do_print;
                    if let Some(needle) = &needle {
                        do_print = has(&node.org, needle);
                        for constraint in &constraints {
                            if !has(&node.ctx, constraint) {
                                do_print = false;
                            }
                        }
                    } else {
                        do_print = !node.org.is_empty();
                    }

                    if do_print {
                        if let Some(filename) = &tree.filename {
                            if !filename_lines_s
                                .last()
                                .is_some_and(|(last_filename, _)| last_filename == filename)
                            {
                                println!("{}", filename.display(),);
                                filename_lines_s.push((filename.clone(), Vec::new()));
                            }
                        } else {
                            eprintln!("Could not find tree.filename");
                        }
                        let line_nr = node.line_ix.unwrap_or(0) + 1;
                        if let Some((_, lines)) = filename_lines_s.last_mut() {
                            lines.push(line_nr);
                        }
                        print!("{}\t", line_nr);
                        for part in &node.parts {
                            if let Some(s) = tree.content.get(part.range.clone()) {
                                print!("{s}");
                            }
                        }
                        println!("");
                    }
                });

                if self.config.do_open {
                    let editor = std::env::var("EDITOR").unwrap_or("hx".to_string());
                    let mut cmd = std::process::Command::new(editor);
                    for (filename, lines) in filename_lines_s {
                        let mut arg = filename.into_os_string();
                        if let Some(line_nr) = lines.first() {
                            arg.push(format!(":{line_nr}"));
                        }
                        cmd.arg(arg);
                    }
                    cmd.status().expect("Could not open files");
                }
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
    do_open: bool,
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
            do_open: cli_args.open,
            args: cli_args.rest.clone(),
            forest: forest_opt,
        };

        Ok(config)
    }
}
