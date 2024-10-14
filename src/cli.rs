pub mod show;

use crate::{
    answer, cli::show::Show, config, fail, fs, path, query, rubr::naft, rubr::naft::ToNaft, tree,
    util,
};
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
        let mut answer: Option<answer::Answer> = None;
        match &self.config.command {
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

                let _forest = self.builder.create_forest_from(&mut self.fs_forest)?;

                // &todo: Implement text-based search in all Part::Meta
            }
            Command::Query(from) => {
                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;
                let query = query::Query::try_from(&self.config.args)?;
                answer = Some(query::search(&forest, &query, from)?);

                if let Some(answer) = &mut answer {
                    answer.order(&answer::By::Name);
                    answer.show(&show::Display::All);
                }
            }
            Command::Next(cnt) => {
                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;
                let query = query::Query::try_from(&self.config.args)?;
                answer = Some(query::search(&forest, &query, &query::From::Org)?);

                if let Some(answer) = &mut answer {
                    answer.order(&answer::By::Prio);
                    let display = match cnt {
                        None => show::Display::All,
                        Some(cnt) => show::Display::First(*cnt as u64 * 5),
                    };
                    answer.show(&display);
                }
            }
            Command::Debug => {
                let needle = self.config.args.get(0);

                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;

                let mut out = naft::Node::new(std::io::stdout());

                for tree_ix in 0..forest.trees.len() {
                    let tree = &forest.trees[tree_ix];

                    let do_print = if let Some(needle) = needle {
                        tree.filename.to_string_lossy().contains(needle)
                    } else {
                        true
                    };

                    if do_print {
                        tree.to_naft(&mut out)?;
                        write!(&mut out, "\n")?;
                    }
                }

                println!("Forest:defs");
                forest.defs.to_naft(&out)?;
                println!("");
            }
        }

        if let Some(answer) = &answer {
            if self.config.do_open {
                let editor = std::env::var("EDITOR").unwrap_or("hx".to_string());
                let mut cmd = std::process::Command::new(editor);
                answer.each_location(|location, meta| {
                    if meta.is_first_for_file {
                        trace!(
                            "Opening {}:{}",
                            &location.filename.display(),
                            location.line_nr
                        );
                        let mut arg = location.filename.as_os_str().to_os_string();
                        arg.push(format!(":{}", location.line_nr));
                        cmd.arg(arg);
                    }
                });
                cmd.status().expect("Could not open files");
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
    Query(query::From),
    Next(Option<u8>),
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

        let global = config::Global::load(&cli_args)?;

        let mut groves = Vec::new();
        {
            for grove_str in &cli_args.grove {
                if let Some(grove) = global.groves.iter().find(|grove| &grove.name == grove_str) {
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

        let command = if cli_args.config {
            Command::Config
        } else if cli_args.query_org {
            Command::Query(query::From::Org)
        } else if cli_args.query_ctx {
            Command::Query(query::From::Ctx)
        } else if cli_args.next > 0 {
            Command::Next(Some(cli_args.next))
        } else if cli_args.next_all {
            Command::Next(None)
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
