use crate::{amp, config, fail, fs, path, rubr::naft, rubr::naft::ToNaft, tree, util};
use std::io::Write;
use tracing::{info, span, trace, Level};

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
        for grove in &self.config.groves {
            self.fs_forest.add_grove(grove.into());
        }

        // Using &self.config.command complicates using &mut self later.
        // Copyng the command once does not impact performance.
        match self.config.command {
            Command::None => {}
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
            Command::Query => {
                let span = span!(Level::TRACE, "query");
                let _g = span.enter();

                let mut filename_lines_s = Vec::<(std::path::PathBuf, Vec<u64>)>::new();

                let needle: Option<amp::KeyValue>;
                let mut constraints = Vec::<amp::KeyValue>::new();
                {
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
                }
                trace!("needle: {:?}", needle);
                trace!("constraints: {:?}", constraints);

                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;
                forest.dfs(|tree, node| {
                    let mut do_print;
                    if let Some(needle) = &needle {
                        do_print = node.org.has(needle);
                        for constraint in &constraints {
                            if !node.ctx.has(constraint) {
                                do_print = false;
                            }
                        }
                    } else {
                        do_print = !node.org.is_empty();
                    }

                    if do_print {
                        if !filename_lines_s
                            .last()
                            .is_some_and(|(last_filename, _)| last_filename == &tree.filename)
                        {
                            println!("{}", tree.filename.display());
                            filename_lines_s.push((tree.filename.clone(), Vec::new()));
                        }
                        // &todo: replace with function
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
            Command::Debug => {
                let mut filename = std::path::PathBuf::new();

                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;

                let mut out = naft::Node::new(std::io::stdout());

                for tree_ix in 0..forest.trees.len() {
                    let tree = &forest.trees[tree_ix];

                    tree.to_naft(&mut out)?;
                    write!(&mut out, "\n")?;
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
    Debug,
}

#[derive(Debug, Clone)]
struct Config {
    global: config::Global,
    command: Command,
    do_open: bool,
    args: Vec<String>,
    groves: Vec<config::Grove>,
}

impl Config {
    fn load(cli_args: config::CliArgs) -> util::Result<Config> {
        let span = span!(Level::INFO, "Config.load");
        let _s = span.enter();
        info!("Some info");

        let global = config::Global::load(&cli_args)?;

        let mut groves = Vec::new();
        {
            for grove_str in &cli_args.grove {
                if let Some(grove) = global.grove.iter().find(|grove| &grove.name == grove_str) {
                    info!("Found grove {:?}", grove);
                    groves.push(grove.clone());
                } else {
                    fail!("Unknown grove '{}'", grove_str);
                }
            }

            for root in &cli_args.root {
                groves.push(config::Grove {
                    name: "<root>".into(),
                    path: fs::expand_path(root)?,
                    hidden: !cli_args.hidden,
                    ignore: !cli_args.ignored,
                    include: Vec::new(),
                    max_size: None,
                });
            }
        }

        let command = if cli_args.query {
            Command::Query
        } else if cli_args.search {
            Command::Search
        } else if cli_args.list {
            Command::List
        } else if cli_args.debug {
            Command::Debug
        } else {
            Command::None
        };

        let config = Config {
            global,
            command,
            do_open: cli_args.open,
            args: cli_args.rest.clone(),
            groves,
        };

        Ok(config)
    }
}
