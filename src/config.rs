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

    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// List all files in all roots
    List {
        /// Verbosity level
        verbose: Option<i32>,
    },
}

impl CliArgs {
    pub fn parse() -> Self {
        clap::Parser::parse()
    }
}

// Global configuration, loaded from '$HOME/.config/champ/config.toml'
#[derive(serde::Deserialize, Debug)]
pub struct Global {
    pub path: Option<path::PathBuf>,
    pub root: Vec<Root>,
}
#[derive(serde::Deserialize, Debug)]
pub struct Root {
    pub name: String,
    pub path: path::PathBuf,
}

impl Global {
    pub fn load(cli_options: &CliArgs) -> util::Result<Global> {
        let global_fp;
        if let Some(fp) = &cli_options.config {
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
        let mut global: Global = toml::from_str(content)?;
        global.path = Some(global_fp);

        Ok(global)
    }
}
