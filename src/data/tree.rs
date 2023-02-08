use crate::data::node;
use crate::data::path::Path;
use crate::my;
use std::io::prelude::*;
use std::io::BufRead;

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

    pub fn read_file(&self, path: &Path) -> my::Result<Vec<String>> {
        let pb = std::path::PathBuf::from(path);

        let mut v = Vec::new();

        let file = std::fs::File::open(pb)?;

        let mut buf_reader = std::io::BufReader::new(file.take(4096));

        if false {
            for entry in buf_reader.lines() {
                v.push(entry?);
            }
        } else {
            let mut buf = Vec::new();
            while let Ok(size) = buf_reader.read_until(0x0a_u8, &mut buf) {
                if size == 0 {
                    break;
                }
                v.push(String::from_utf8_lossy(&buf).into_owned());
            }
        }

        Ok(v)
    }

    pub fn read_folder(&self, path: &Path) -> my::Result<Vec<String>> {
        let pb = std::path::PathBuf::from(path);

        let mut v = Vec::new();

        for entry in std::fs::read_dir(&pb)? {
            v.push(entry?.file_name().to_string_lossy().to_string());
        }

        Ok(v)
    }
}
