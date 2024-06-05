use crate::util;

use clap::Parser;

#[derive(Parser, Debug)]
pub struct Options {
    pub help: bool,
    #[arg(short, long, default_value_t = 0)]
    pub verbose: i32,
}

impl Options {
    pub fn parse_from_cli() -> Self {
        clap::Parser::parse()
    }
}
