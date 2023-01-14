pub use crate::data::name::Data;
pub use crate::data::node::{Node, Nodes};
pub use crate::data::path::Path;
pub use crate::data::tree::Tree;

mod name;
mod node;
mod path;
mod tree;

#[derive(Default)]
pub struct List {
    pub items: Vec<String>,
    pub focus: Option<usize>,
}

impl List {
    pub fn new() -> List {
        Default::default()
    }
}
