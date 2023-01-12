mod cli;
mod data;
#[macro_use]
mod my;
mod show;
mod tui;

fn main() -> my::Result<()> {
    tui::test()?;

    return Ok(());

    let tree = data::Tree::new();

    let path = data::Path::from(std::env::current_dir()?);

    println!("{}", &path);
    for node in tree.nodes(&path)? {
        println!("{}", node);
    }

    let list = show::widget::List::new();

    Ok(())
}
