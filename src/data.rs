pub use crate::data::list::List;
pub use crate::data::name::Data;
pub use crate::data::node::{Node, Nodes};
pub use crate::data::path::Path;
pub use crate::data::tree::Tree;
use std::cmp;

mod list;
mod name;
mod node;
mod path;
mod tree;

#[derive(Debug)]
pub struct Index {
    pub ix: i64,
    pub name: Option<String>,
}

impl Index {
    pub fn new() -> Index {
        Index { ix: -1, name: None }
    }

    pub fn update(&mut self, items: &Vec<String>) {
        if let Some(wanted_name) = &self.name {
            for (ix, item) in items.iter().enumerate() {
                if item == wanted_name {
                    self.ix = ix as i64;
                    // We found the name and updated the ix
                    return;
                }
            }
        }

        self.ix = cmp::max(self.ix, 0);

        let max_ix = (items.len() as i64) - 1;
        self.ix = cmp::min(self.ix, max_ix);

        if self.ix < 0 {
            self.name = None;
        } else {
            self.name = Some(items[self.ix as usize].clone());
        }
    }
}

pub struct Filter {
    hidden: bool,
}

impl Filter {
    pub fn new() -> Filter {
        Filter { hidden: false }
    }
}
