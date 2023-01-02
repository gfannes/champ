pub type Nodes = Vec<Box<Node>>;

#[derive(Default)]
pub struct Node {
    name: String,
    childs: Nodes,
}

impl Node {
    pub fn new(str: String) -> Node {
        Node {
            name: str,
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
