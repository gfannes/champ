use clap::Parser;
use std::path;

#[derive(Parser, Debug)]
pub struct Options {
    pub help: bool,
    #[arg(short, long, default_value_t = 0)]
    pub verbose: i32,

    #[arg(short, long)]
    pub config: Option<path::PathBuf>,
}

impl Options {
    pub fn parse_from_cli() -> Self {
        clap::Parser::parse()
    }
}
