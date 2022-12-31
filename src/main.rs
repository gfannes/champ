mod cli;
mod data;
mod error;

use crate::error::Result;

fn main() -> Result<()> {
    let tree = data::Tree::new();

    let mut path = data::Path::from(std::env::current_dir()?);

    println!("{}", &path);
    for node in tree.nodes(&path)? {
        println!("{}", node);
    }

    Ok(())
}
