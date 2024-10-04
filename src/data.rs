pub use crate::data::index::{Index, Indices};
pub use crate::data::list::List;
pub use crate::data::path::Path;
pub use crate::data::tree::Tree;

mod index;
mod list;
mod name;
mod node;
pub mod path;
pub mod status;
mod tree;

pub struct Filter {
    pub hidden: bool,
    pub sort: bool,
    pub filter: String,
}
