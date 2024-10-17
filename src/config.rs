use crate::{fail, rubr::naft, util};
use clap::Parser;
use dirs;
use serde;
use std::path;
use toml;
use tracing::{error, info, trace};

#[derive(Parser, Debug)]
#[command(
    name = "champ",
    version,
    about,
    long_about = None,
    after_help = concat!("Developed by ", env!("CARGO_PKG_AUTHORS")),
)]
pub struct CliArgs {
    /// Verbosity level: 0: error, 1: warn, 2: info, 3: trace
    #[arg(short, long, default_value_t = default_verbose(), value_name = "LEVEL")]
    pub verbose: u32,

    /// The configuration folder to use when looking for `groves.toml`
    #[arg(long, value_name = "FOLDER")]
    pub config_root: Option<path::PathBuf>,

    /// Named groves from `$config_root/groves.toml` to use
    #[arg(short, long, value_name = "NAME")]
    pub grove: Vec<String>,

    /// Root of grove to include
    #[arg(short = 'r', long, value_name = "FOLDER")]
    pub root: Vec<path::PathBuf>,

    /// Apply arguments previously registered under given name
    #[arg(short = 'c', long, value_name = "NAME", verbatim_doc_comment)]
    pub command: Option<String>,

    /// Register all specified arguments under given name for later use
    /// Names starting with '~' have a special meaning:
    /// - '~remove|~rm': Removes the commands file
    /// - '~list|~ls': Lists all available commands
    #[arg(short = 'C', long, value_name = "NAME", verbatim_doc_comment)]
    pub register_command: Option<String>,

    /// Include hidden files for grove `$root`
    #[arg(short = 'u', long, default_value_t = false)]
    pub hidden: bool,

    /// Include ignored files for grove `$root`
    #[arg(short = 'U', long, default_value_t = false)]
    pub ignored: bool,

    /// Open selected files in editor
    #[arg(short = 'o', long, default_value_t = false)]
    pub open: bool,

    /// Query AMP metadata from Org
    #[arg(short = 'q', long, default_value_t = false)]
    pub query_org: bool,

    /// Query AMP metadata from Ctx
    #[arg(short = 'Q', long, default_value_t = false)]
    pub query_ctx: bool,

    /// Show first-n next tasks to execute
    #[arg(short = 'n', long, action = clap::ArgAction::Count)]
    pub next: u8,

    /// Show all next tasks to execute
    #[arg(short = 'N', long, default_value_t = false)]
    pub next_all: bool,

    /// Free-form search in all metadata
    #[arg(short = 's', long, default_value_t = false)]
    pub search: bool,

    /// List all files in the forest
    #[arg(short = 'l', long, default_value_t = false)]
    pub list: bool,

    /// Debug view
    #[arg(short = 'd', long, default_value_t = false)]
    pub debug: bool,

    /// Additional arguments, interpretation depends on provided arguments
    /// -c: clear | set | print
    /// -q: org ctx*
    // #[clap(value_parser, verbatim_doc_comment)]
    pub rest: Vec<String>,
}
pub fn default_verbose() -> u32 {
    1
}

impl CliArgs {
    pub fn try_parse() -> util::Result<Self> {
        let res: CliArgs = clap::Parser::parse();
        Ok(res)
    }
}

// Global configuration, loaded from '$HOME/.config/champ'
#[derive(Debug, Clone, Default)]
pub struct Global {
    pub path: Option<path::PathBuf>,
    pub groves: Vec<Grove>,
    pub commands: Vec<Command>,
}

#[derive(serde::Deserialize, Debug, Clone)]
pub struct Groves {
    pub grove: Vec<Grove>,
}

#[derive(serde::Deserialize, Debug, Clone)]
pub struct Grove {
    pub name: String,
    pub path: path::PathBuf,
    #[serde(default = "default_true")]
    pub hidden: bool,
    #[serde(default = "default_true")]
    pub ignore: bool,
    #[serde(default)]
    pub include: Vec<String>,
    #[serde(default)]
    pub max_size: Option<usize>,
}
fn default_true() -> bool {
    true
}

#[derive(serde::Deserialize, serde::Serialize, Debug, Clone)]
pub struct Commands {
    pub command: Vec<Command>,
}

#[derive(serde::Deserialize, serde::Serialize, Debug, Clone)]
pub struct Command {
    pub name: String,
    pub groves: Vec<String>,
    pub roots: Vec<path::PathBuf>,
    pub rest: Vec<String>,
    pub verbose: u32,
    pub next: u8,
    pub hidden: bool,
    pub ignored: bool,
    pub open: bool,
    pub query_org: bool,
    pub query_ctx: bool,
    pub next_all: bool,
    pub search: bool,
    pub list: bool,
    pub debug: bool,
}

impl naft::ToNaft for Command {
    fn to_naft(&self, b: &mut naft::Body<'_, '_>) -> std::fmt::Result {
        b.node(&"Command")?;
        b.attr("name", &self.name)?;
        b.attr("verbose", &self.verbose)?;
        b.attr("next", &self.next)?;
        b.attr("hidden", &self.hidden)?;
        b.attr("ignored", &self.ignored)?;
        b.attr("open", &self.open)?;
        b.attr("query_org", &self.query_org)?;
        b.attr("query_ctx", &self.query_ctx)?;
        b.attr("next_all", &self.next_all)?;
        b.attr("search", &self.search)?;
        b.attr("list", &self.list)?;
        b.attr("debug", &self.debug)?;

        let mut b = b.nest();
        if !self.groves.is_empty() {
            b.set_ctx("groves");
            b.node(&"Names")?;
            for grove in &self.groves {
                b.key(grove)?;
            }
        }
        if !self.roots.is_empty() {
            b.set_ctx("roots");
            b.node(&"Folders")?;
            for root in &self.roots {
                b.key(&root.to_string_lossy())?;
            }
        }
        if !self.rest.is_empty() {
            b.set_ctx("rest");
            b.node(&"Names")?;
            for rest in &self.rest {
                b.key(rest)?;
            }
        }
        Ok(())
    }
}

impl Global {
    pub fn load(config_root: &Option<path::PathBuf>) -> util::Result<Global> {
        let config_root = config_root
            .clone()
            .or_else(|| {
                dirs::config_dir()
                    .map(|dir| {
                        let dir = dir.join("champ");
                        if !dir.exists() {
                            if std::fs::create_dir_all(&dir).is_err() {
                                error!("Could not create configuration folder '{}'", dir.display());
                                return None;
                            }
                        } else if !dir.is_dir() {
                            error!("Expected '{}' to be absent or a directory", dir.display());
                            return None;
                        }
                        Some(dir)
                    })
                    .flatten()
            })
            .ok_or_else(|| {
                error!("Could not derive configuration root");
                util::Error::create("Could not derive configuration root")
            })?;
        if !config_root.exists() {
            fail!(
                "Could not find configuration root '{}'",
                config_root.display()
            );
        }

        let mut global = Global {
            path: Some(config_root.clone()),
            ..Default::default()
        };

        {
            let groves_fp = config_root.join("groves.toml");
            if !groves_fp.is_file() {
                fail!("Could not find groves file '{}'", groves_fp.display());
            }

            info!("Loading groves from '{}'", groves_fp.display());
            let content = std::fs::read(&groves_fp)?;
            let content = std::str::from_utf8(&content)?;
            trace!("Groves content :\n{content}");
            // &todo &g0: toml::from_str() silently skips unrecognised items. Make this parsing more strict.
            match toml::from_str::<Groves>(content) {
                Ok(groves) => global.groves = groves.grove,
                Err(err) => {
                    fail!(
                        "Could not parse groves from '{}': {}",
                        groves_fp.display(),
                        err
                    );
                }
            }
        }

        {
            let commands_fp = config_root.join("commands.toml");
            if commands_fp.is_file() {
                info!("Loading commands from '{}'", commands_fp.display());
                let content = std::fs::read(&commands_fp)?;
                let content = std::str::from_utf8(&content)?;
                trace!("commands content :\n{content}");
                // &todo &g0: toml::from_str() silently skips unrecognised items. Make this parsing more strict.
                match toml::from_str::<Commands>(content) {
                    Ok(commands) => global.commands = commands.command,
                    Err(err) => {
                        fail!(
                            "Could not parse commands from '{}': {}",
                            commands_fp.display(),
                            err
                        );
                    }
                }
            } else {
                info!(
                    "Could not load commands, no such file '{}'",
                    commands_fp.display()
                );
            }
        }

        Ok(global)
    }
}
