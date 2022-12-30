mod cli;

use champetter::error;
use std::env;

mod data {
    use std::fs;
    use std::path;

    pub type Nodes = Vec<Box<Node>>;

    pub struct Node {
        name: String,
        childs: Nodes,
    }

    impl Node {
        pub fn new(str: String) -> Box<Node> {
            Box::new(Node {
                name: str,
                childs: vec![],
            })
        }

        pub fn create_tree(path: path::PathBuf) -> Nodes {
            println!("{}", path.display());

            let mut roots: Nodes = vec![Node::new("/".to_string())];
            let mut r = &mut roots[0];

            let mut p = path::PathBuf::new();

            for part in path.components() {
                match (part) {
                    path::Component::RootDir => {
                        p.push("/");
                    }
                    path::Component::Normal(str) => {
                        let name = str.to_string_lossy().to_string();
                        p.push(&name);
                        println!("{}", p.display());
                        r.name = name;

                        if let Ok(it) = fs::read_dir(&p) {
                            for okrc in it {
                                if let Ok(entry) = okrc {
                                    println!("{:?}", entry)
                                }
                            }
                        }
                    }
                    _ => {}
                }
            }

            roots
        }
    }
}

fn main() -> error::Result<()> {
    let path = env::current_dir()?;
    let root = data::Node::create_tree(path);

    Ok(())
}
