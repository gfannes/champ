mod cli;
mod error;

use error::Result;

fn main() -> Result<()> {
    let _options = cli::Options::parse()?;

    return Ok(());
}
