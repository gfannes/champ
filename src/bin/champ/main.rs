mod cli;

use champetter::error::Result;
use std::env;

mod data {
    use champetter::error::{Error, Result};
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

        pub fn create_tree(path: path::PathBuf) -> Result<Nodes> {
            println!("{}", path.display());

            let mut roots: Nodes = vec![Node::new("/".to_string())];
            let mut nodes = &mut roots;
            let mut ix: usize = 0;

            let mut p = path::PathBuf::new();

            for part in path.components() {
                match part {
                    path::Component::RootDir => {
                        p.push("/");
                    }
                    path::Component::Normal(str) => {
                        let mut parent = &mut nodes[ix];
                        Node::setup(&mut parent.childs, &p)?;

                        let name = str.to_string_lossy().to_string();
                        ix = std::usize::MAX;
                        for (i, n) in parent.childs.iter().enumerate() {
                            if n.name == name {
                                ix = i;
                                break;
                            }
                        }
                        if ix == std::usize::MAX {
                            return Err(Box::<dyn std::error::Error + 'static>::from("Not found"));
                        }

                        p.push(&name);
                        println!("{}", p.display());

                        nodes = &mut parent.childs;
                        let mut node = &mut nodes[ix];
                        node.name = name;

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

            Ok(roots)
        }

        pub fn setup(nodes: &mut Nodes, path: &path::PathBuf) -> Result<()> {
            for entry in fs::read_dir(path)? {
                nodes.push(Node::new(entry?.file_name().to_string_lossy().to_string()))
            }
            Ok(())
        }
    }
}

fn main() -> Result<()> {
    let path = env::current_dir()?;
    let root = data::Node::create_tree(path)?;

    Ok(())
}
