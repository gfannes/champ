pub use crate::data::name::Data;
pub use crate::data::node::{Node, Nodes};
pub use crate::data::path::Path;
pub use crate::data::tree::Tree;
use crate::my;

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

    pub fn set_items(&mut self, nodes: &Vec<String>, filter: &Filter) -> my::Result<()> {
        let focus_str = self.focus.map(|ix| self.items[ix].clone());
        self.focus = None;

        self.items.clear();
        for (ix, s) in nodes.iter().enumerate() {
            let mut include = true;

            let is_hidden = s.starts_with(".");
            if is_hidden && !filter.hidden {
                include = false;
            }

            if include {
                let s = s.to_string();
                if let Some(focus_str) = &focus_str {
                    if self.focus.is_none() && s == *focus_str {
                        self.focus = Some(ix);
                    }
                }

                self.items.push(s);
            }
        }

        Ok(())
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
