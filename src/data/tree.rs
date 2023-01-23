use crate::data::node;
use crate::data::path::Path;
use crate::my;

pub struct Tree {
    root: node::Node,
}

impl Tree {
    pub fn new() -> Tree {
        Tree {
            root: node::Node::new("/".to_string()),
        }
    }

    pub fn is_file(&self, path: &Path) -> bool {
        let pb = std::path::PathBuf::from(path);
        if let Ok(metadata) = std::fs::metadata(&pb) {
            if metadata.is_file() {
                return true;
            }
        }
        false
    }

    pub fn nodes(&self, path: &Path) -> my::Result<Vec<String>> {
        let pb = std::path::PathBuf::from(path);

        let mut v = Vec::new();

        for entry in std::fs::read_dir(&pb)? {
            v.push(entry?.file_name().to_string_lossy().to_string());
        }

        Ok(v)
    }
}
