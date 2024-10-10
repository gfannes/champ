use crate::{fail, util};
use clap::Parser;
use dirs;
use serde;
use std::path;
use toml;
use tracing::{error, info, trace};

#[derive(Parser, Debug)]
#[command(
    name = "ch",
    version,
    about,
    long_about = None,
    after_help = concat!("Developed by ", env!("CARGO_PKG_AUTHORS")),
)]
pub struct CliArgs {
    /// Verbosity level: 0: error, 1: warn, 2: info, 3: trace
    #[arg(short, long, default_value_t = 1)]
    pub verbose: u32,

    /// The configuration folder to use when looking for `groves.toml`
    #[arg(long)]
    pub config_root: Option<path::PathBuf>,

    /// Named groves from `$config_root/groves.toml` to use
    #[arg(short, long)]
    pub grove: Vec<String>,

    /// Root of grove to include
    #[arg(short = 'C', long)]
    pub root: Vec<path::PathBuf>,

    /// Include hidden files for grove `$root`
    #[arg(short = 'u', long, default_value_t = false)]
    pub hidden: bool,

    /// Include ignored files for grove `$root`
    #[arg(short = 'U', long, default_value_t = false)]
    pub ignored: bool,

    /// Open selected files in editor
    #[arg(short = 'o', long, default_value_t = false)]
    pub open: bool,

    /// Update current configuration
    #[arg(short = 'c', long, default_value_t = false)]
    pub config: bool,

    /// Query AMP metadata
    #[arg(short = 'q', long, default_value_t = false)]
    pub query: bool,

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
    #[clap(value_parser, verbatim_doc_comment)]
    pub rest: Vec<String>,
}

impl CliArgs {
    pub fn try_parse() -> util::Result<Self> {
        let res: CliArgs = clap::Parser::parse();
        Ok(res)
    }
}

// Global configuration, loaded from '$HOME/.config/champ/config.toml'
#[derive(Debug, Clone)]
pub struct Global {
    pub path: Option<path::PathBuf>,
    pub groves: Vec<Grove>,
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

#[derive(serde::Deserialize, Debug, Clone)]
pub struct Groves {
    pub grove: Vec<Grove>,
}

impl Global {
    pub fn load(cli_args: &CliArgs) -> util::Result<Global> {
        let config_root = cli_args
            .config_root
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

        let groves_fp = config_root.join("groves.toml");
        if !groves_fp.is_file() {
            fail!("Could not find groves file '{}'", groves_fp.display());
        }

        info!("Loading groves from '{}'", groves_fp.display());
        let content = std::fs::read(&groves_fp)?;
        let content = std::str::from_utf8(&content)?;
        trace!("Groves content :\n{content}");
        // &someday: toml::from_str() silently skips unrecognised items. Make this parsing more strict.
        match toml::from_str::<Groves>(content) {
            Ok(groves) => Ok(Global {
                path: Some(groves_fp),
                groves: groves.grove,
            }),
            Err(err) => {
                fail!(
                    "Could not parse config from '{}': {}",
                    groves_fp.display(),
                    err
                );
            }
        }
    }
}
