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
}
