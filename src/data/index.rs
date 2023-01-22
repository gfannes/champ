use crate::data;
use std::cmp;
use std::collections;

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

type Path__Index = collections::HashMap<data::path::Path, Index>;
pub struct Indices {
    path__index: Path__Index,
}

impl Indices {
    pub fn new() -> Indices {
        Indices {
            path__index: Path__Index::new(),
        }
    }
    pub fn goc(&mut self, path: &data::Path) -> &mut Index {
        if !self.path__index.contains_key(path) {
            self.path__index.insert(path.clone(), Index::new());
        }
        self.path__index
            .get_mut(path)
            .expect("Index should be present")
    }
}
