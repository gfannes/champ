use crate::{fail, util};
use clap::{Parser, Subcommand};
use dirs;
use serde;
use std::path;
use toml;

#[derive(Parser, Debug)]
pub struct CliArgs {
    /// Verbosity level
    #[arg(short, long, default_value_t = 0)]
    pub verbose: i32,

    /// Specify the configuration file to load, default is $HOME/.config/champ/config.toml
    #[arg(short, long)]
    pub config: Option<path::PathBuf>,

    /// Named forest, defined in the config file
    #[arg(short, long)]
    pub forest: Option<String>,

    #[arg(short = 'C', long)]
    pub root: Option<path::PathBuf>,

    #[arg(short = 'u', long, default_value_t = false)]
    pub hidden: bool,

    #[arg(short = 'U', long, default_value_t = false)]
    pub ignored: bool,

    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand, Debug, Clone)]
pub enum Command {
    /// Print global config
    Config {
        /// Verbosity level
        verbose: Option<i32>,
    },
    /// List all files for a given forest
    #[command(name = "list", alias = "li")]
    List {
        /// Verbosity level
        verbose: Option<i32>,
    },
    /// Search for items in a given forest
    #[command(name = "search", alias = "se")]
    Search {
        /// Needle, None will match any metadata
        needle: Option<String>,
        /// Verbosity level
        verbose: Option<i32>,
    },
}

impl CliArgs {
    pub fn try_parse() -> util::Result<Self> {
        let res: CliArgs = clap::Parser::parse();
        if res.forest.is_some() && res.root.is_some() {
            fail!("You cannot specify both a 'forest' and a 'root'");
        }
        Ok(res)
    }
}

// Global configuration, loaded from '$HOME/.config/champ/config.toml'
#[derive(serde::Deserialize, Debug, Clone)]
pub struct Global {
    pub path: Option<path::PathBuf>,
    pub forest: Vec<Forest>,
}
#[derive(serde::Deserialize, Debug, Clone)]
pub struct Forest {
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

impl Global {
    pub fn load(cli_args: &CliArgs) -> util::Result<Global> {
        let global_fp;
        if let Some(fp) = &cli_args.config {
            global_fp = Some(fp.to_owned());
        } else {
            global_fp = dirs::config_dir().map(|d| d.join("champ/config.toml"));
            if let Some(fp) = &global_fp {
                if let Some(dir) = fp.parent() {
                    if !dir.exists() {
                        std::fs::create_dir_all(dir)?;
                    } else if !dir.is_dir() {
                        fail!("Expected '{}' to be absent or a directory", dir.display());
                    }

                    if !fp.exists() {
                        std::fs::write(fp, "")?;
                    } else if !fp.is_file() {
                        fail!("Expected '{}' to be absent or a file", fp.display());
                    }
                }
            }
        }
        let global_fp =
            global_fp.ok_or(util::Error::create("Could not determine config filepath"))?;
        if !global_fp.is_file() {
            fail!("Could not find config file '{}'", global_fp.display());
        }

        let content = std::fs::read(&global_fp)?;
        let content = std::str::from_utf8(&content)?;
        match toml::from_str::<Global>(content) {
            Ok(mut global) => {
                global.path = Some(global_fp);
                Ok(global)
            }
            Err(err) => {
                fail!(
                    "Could not parse config from '{}': {}",
                    global_fp.display(),
                    err
                );
            }
        }
    }
}
