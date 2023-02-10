pub use crate::data::index::{Index, Indices};
pub use crate::data::list::List;
pub use crate::data::name::Data;
pub use crate::data::node::{Node, Nodes};
pub use crate::data::path::Path;
pub use crate::data::tree::Tree;

mod index;
mod list;
mod name;
mod node;
pub mod path;
mod tree;

pub struct Filter {
    pub hidden: bool,
    pub sort: bool,
}
