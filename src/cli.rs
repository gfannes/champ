pub mod show;

use crate::{
    answer::{self, Answer},
    cli::show::Show,
    config, fail, fs, path, query,
    rubr::naft,
    tree, util,
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
            Command::List => {
                self.list_files_recursive_(&path::Path::root())?;
            }
            Command::Search => {
                let needle = self.config.what.clone();
                println!("needle: {:?}", &needle);

                let _forest = self.builder.create_forest_from(&mut self.fs_forest)?;

                // &todo: Implement text-based search in all Part::Meta
            }
            Command::Query(from) => {
                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;
                // println!("forest: {}", naft::AsNaft::<tree::Forest>::new(&forest));

                let query = query::Query::try_from((&self.config.what, &self.config.args))?;
                answer = Some(query::search(&forest, &query, from)?);

                if let Some(answer) = &mut answer {
                    answer.order(&answer::By::Name);
                    answer.show(&show::Display::All);
                }
            }
            Command::Next(cnt) => {
                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;
                let query = query::Query::try_from((&self.config.what, &self.config.args))?;
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
                let needle = &self.config.what;

                let forest = self.builder.create_forest_from(&mut self.fs_forest)?;

                for tree_ix in 0..forest.trees.len() {
                    let tree = &forest.trees[tree_ix];

                    let do_print = if let Some(needle) = needle {
                        match needle.as_str() {
                            // &doc
                            "~all" => true,
                            _ => tree.filename.to_string_lossy().contains(needle),
                        }
                    } else {
                        false
                    };

                    for node in &tree.nodes {
                        for path in &node.org.data {
                            if !path.is_absolute {
                                if answer.is_none() {
                                    answer = Some(Answer::new());
                                }
                                let answer = answer.as_mut().unwrap();

                                if tree.filename.is_file() {
                                    let content = node
                                        .parts
                                        .iter()
                                        .filter_map(|part| tree.content.get(part.range.clone()))
                                        .collect();
                                    let org = node.org.to_string();
                                    let ctx = node.ctx.to_string();

                                    answer.add(answer::Location {
                                        filename: tree.filename.clone(),
                                        line_nr: node.line_ix.unwrap_or(0) + 1,
                                        content,
                                        org,
                                        ctx,
                                        ..Default::default()
                                    });
                                }
                            }
                        }
                    }

                    if do_print {
                        println!("{}", naft::AsNaft::<tree::Tree>::new(tree));
                    }
                }

                if let Some(answer) = &mut answer {
                    if !answer.is_empty() {
                        println!("Could not resolve following Paths");
                        answer.order(&answer::By::Name);
                        answer.show(&show::Display::All);
                    }
                }

                println!("Forest:defs");
                for path in &forest.defs.data {
                    println!("\t{path}");
                }
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
    what: Option<String>,
    args: Vec<String>,
    groves: Vec<config::Grove>,
}

impl Config {
    fn load(mut cli_args: config::CliArgs) -> util::Result<Config> {
        let span = span!(Level::INFO, "Config.load");
        let _s = span.enter();

        let mut config_global = config::Global::load(&cli_args.config_root)?;

        // Apply arguments from registered command
        if let Some(name) = cli_args.command.clone() {
            if let Some(command) = config_global
                .commands
                .iter()
                .find(|command| &command.name == &name)
            {
                // If cli_args is the default, we overwrite it with data from command
                if cli_args.verbose == config::default_verbose() {
                    cli_args.verbose = command.verbose;
                }
                if cli_args.next == 0 {
                    cli_args.next = command.next;
                }
                if !cli_args.hidden {
                    cli_args.hidden = command.hidden;
                }
                if !cli_args.ignored {
                    cli_args.ignored = command.ignored;
                }
                if !cli_args.open {
                    cli_args.open = command.open;
                }
                if !cli_args.query_org {
                    cli_args.query_org = command.query_org;
                }
                if !cli_args.query_ctx {
                    cli_args.query_ctx = command.query_ctx;
                }
                if !cli_args.next_all {
                    cli_args.next_all = command.next_all;
                }
                if !cli_args.search {
                    cli_args.search = command.search;
                }
                if !cli_args.list {
                    cli_args.list = command.list;
                }
                if !cli_args.debug {
                    cli_args.debug = command.debug;
                }
                if cli_args.what.is_none() {
                    cli_args.what = command.what.clone();
                }
                {
                    // Put items from command first
                    let mut new_groves = command.groves.clone();
                    for grove in cli_args.grove {
                        if !new_groves.contains(&grove) {
                            new_groves.push(grove);
                        }
                    }
                    cli_args.grove = new_groves;
                }
                {
                    // Put items from command first
                    let mut new_roots = command.roots.clone();
                    for root in cli_args.root {
                        if !new_roots.contains(&root) {
                            new_roots.push(root);
                        }
                    }
                    cli_args.root = new_roots;
                }
                {
                    // Put items from command first
                    let mut new_wher = command.wher.clone();
                    new_wher.append(&mut cli_args.wher);
                    cli_args.wher = new_wher;
                }
            } else {
                fail!("Could not find command '{}'", &name);
            }

            trace!("Updated cli_args: {:?}", &cli_args);
        }

        // Register arguments under new name
        if let Some(name) = cli_args.register_command {
            match name.as_str() {
                "~clear" => {
                    if let Some(fp) = config_global.path.clone() {
                        let fp = fp.join("commands.toml");
                        info!("Removing commands file '{}'", fp.display());
                        std::fs::remove_file(fp)?;
                    }
                }
                "~list" => {
                    for command in &config_global.commands {
                        println!("{}", naft::AsNaft::<config::Command>::new(command));
                    }
                }
                _ => {
                    if name.starts_with("~") {
                        fail!(
                            "Cannot register command '{}' starting with '~', this is reserved.",
                            &name
                        );
                    }

                    // Remove items with the same name
                    config_global
                        .commands
                        .retain(|command| &command.name != &name);

                    let command = config::Command {
                        name: name.clone(),
                        groves: cli_args.grove.clone(),
                        roots: cli_args.root.clone(),
                        wher: cli_args.wher.clone(),
                        next: cli_args.next,
                        verbose: cli_args.verbose,
                        hidden: cli_args.hidden,
                        ignored: cli_args.ignored,
                        open: cli_args.open,
                        query_org: cli_args.query_org,
                        query_ctx: cli_args.query_ctx,
                        next_all: cli_args.next_all,
                        search: cli_args.search,
                        list: cli_args.list,
                        debug: cli_args.debug,
                        what: cli_args.what.clone(),
                    };

                    config_global.commands.push(command);

                    let commands = config::Commands {
                        command: config_global.commands.clone(),
                    };
                    let str = toml::to_string(&commands)?;
                    if let Some(fp) = config_global.path.clone() {
                        let fp = fp.join("commands.toml");
                        info!("Writing new command '{}' to '{}'", &name, fp.display());
                        std::fs::write(fp, str)?;
                    }
                }
            }
        }

        let mut groves = Vec::new();
        {
            for grove_str in &cli_args.grove {
                if let Some(grove) = config_global
                    .groves
                    .iter()
                    .find(|grove| &grove.name == grove_str)
                {
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

        let command = if cli_args.query_org {
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
            global: config_global,
            command,
            do_open: cli_args.open,
            what: cli_args.what.clone(),
            args: cli_args.wher.clone(),
            groves,
        };

        Ok(config)
    }
}
