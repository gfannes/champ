pub type Nodes = Vec<Box<Node>>;

use crate::data::name::{Build, Name};

#[derive(Default)]
pub struct Node {
    name: Name,
    childs: Nodes,
}

impl Node {
    pub fn new(name: impl Into<String>) -> Node {
        Node {
            name: Name::root(name),
            ..Default::default()
        }
    }

    // pub fn setup(nodes: &mut Nodes, path: &PathBuf) -> Result<()> {
    //     for entry in fs::read_dir(path)? {
    //         nodes.push(Node::new(entry?.file_name().to_string_lossy().to_string()))
    //     }
    //     Ok(())
    // }
}
