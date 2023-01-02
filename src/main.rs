mod cli;
mod data;
#[macro_use]
mod my;

fn main() -> my::Result<()> {
    let tree = data::Tree::new();

    let path = data::Path::from(std::env::current_dir()?);

    println!("{}", &path);
    for node in tree.nodes(&path)? {
        println!("{}", node);
    }

    Ok(())
}
