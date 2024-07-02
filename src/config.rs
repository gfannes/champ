use crate::{fail, util};
use clap::Parser;
use dirs;
use serde;
use std::path;
use toml;

#[derive(Parser, Debug)]
pub struct CliArgs {
    pub help: bool,
    #[arg(short, long, default_value_t = 0)]
    pub verbose: i32,

    #[arg(short, long)]
    pub config: Option<path::PathBuf>,
}

impl CliArgs {
    pub fn parse() -> Self {
        clap::Parser::parse()
    }
}

// Global configuration, loaded from '$HOME/.config/champ/config.toml'
#[derive(serde::Deserialize, Debug)]
pub struct Global {
    pub test: Option<String>,
}
