use crate::data::node;
use crate::data::path::Path;
use crate::error::{Error, Result};

use std::path::PathBuf;

pub struct Tree {
    root: node::Node,
}

impl Tree {
    pub fn new() -> Tree {
        Tree {
            root: node::Node::new("/".to_string()),
        }
        //     let mut roots: Nodes = vec![Node::new("/".to_string())];
        //     let mut nodes = &mut roots;
        //     let mut ix: usize = 0;

        //     let mut p = PathBuf::new();

        //     for part in path.components() {
        //         match part {
        //             std::path::Component::RootDir => {
        //                 p.push("/");
        //             }
        //             std::path::Component::Normal(str) => {
        //                 let mut parent = &mut nodes[ix];
        //                 Node::setup(&mut parent.childs, &p)?;

        //                 let name = str.to_string_lossy().to_string();
        //                 ix = std::usize::MAX;
        //                 for (i, n) in parent.childs.iter().enumerate() {
        //                     if n.name == name {
        //                         ix = i;
        //                         break;
        //                     }
        //                 }
        //                 if ix == std::usize::MAX {
        //                     return Err(Box::<dyn std::error::Error + 'static>::from("Not found"));
        //                 }

        //                 p.push(&name);
        //                 println!("{}", p.display());

        //                 nodes = &mut parent.childs;
        //                 let mut node = &mut nodes[ix];
        //                 node.name = name;

        //                 if let Ok(it) = fs::read_dir(&p) {
        //                     for okrc in it {
        //                         if let Ok(entry) = okrc {
        //                             println!("{:?}", entry)
        //                         }
        //                     }
        //                 }
        //             }
        //             _ => {}
        //         }
        //     }

        //     Ok(roots)
    }

    pub fn nodes(&self, path: &Path) -> Result<Vec<String>> {
        let pb = std::path::PathBuf::from(path);
        println!("pb: {}", pb.display());

        let mut v = Vec::new();

        for entry in std::fs::read_dir(&pb)? {
            v.push(entry?.file_name().to_string_lossy().to_string());
        }

        Ok(v)
    }
}
