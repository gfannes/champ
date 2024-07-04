// Annotation Metadata Protocol

use crate::{fail, util};
use std::{ffi, fmt, fs, path};

#[derive(Clone)]
pub enum Part {
    Folder { name: ffi::OsString },
    File { name: ffi::OsString },
    Range { begin: usize, size: usize },
}

#[derive(Clone)]
pub struct Path {
    parts: Vec<Part>,
}
impl Path {
    pub fn root() -> Path {
        Path { parts: Vec::new() }
    }
    fn push(&self, part: Part) -> Path {
        let mut path = self.clone();
        path.parts.push(part);
        path
    }
    fn fs_path(&self) -> util::Result<FsPath> {
        let mut ret = FsPath::Folder(path::PathBuf::from("/"));
        for part in &self.parts {
            match part {
                Part::Folder { name } => match ret {
                    FsPath::Folder(mut folder) => {
                        folder.push(name);
                        ret = FsPath::Folder(folder)
                    }
                    _ => fail!("Cannot add folder part to non-folder"),
                },
                Part::File { name } => match ret {
                    FsPath::Folder(mut folder) => {
                        folder.push(name);
                        ret = FsPath::File(folder)
                    }
                    _ => fail!("Cannot add file part to non-folder"),
                },
                Part::Range { .. } => match &ret {
                    FsPath::File(_) => {}
                    _ => fail!("Cannot add range part to non-file"),
                },
            }
        }
        Ok(ret)
    }
}
impl fmt::Display for Path {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "/")?;
        for part in &self.parts {
            match part {
                Part::Folder { name } => write!(f, "{}/", name.to_string_lossy())?,
                Part::File { name } => write!(f, "{} ", name.to_string_lossy())?,
                Part::Range { begin, size } => write!(f, "[{}, {}]", begin, size)?,
            }
        }
        Ok(())
    }
}

enum FsPath {
    Folder(path::PathBuf),
    File(path::PathBuf),
}

pub struct Node {
    path: Path,
    name: String,
}
impl Node {
    fn new(path: Path) -> Node {
        Node {
            path,
            name: String::new(),
        }
    }
}

type Nodes = Vec<Node>;

pub struct Filter {}

pub struct Tree {
    filter: Filter,
}

impl Tree {
    pub fn new() -> Tree {
        Tree { filter: Filter {} }
    }
    pub fn list(&mut self, path: &Path) -> util::Result<Nodes> {
        let mut nodes = Vec::new();
        match path.fs_path()? {
            FsPath::Folder(folder) => {
                println!("Reading {:?}", &folder);
                for entry in fs::read_dir(&folder)? {
                    let entry = entry?;
                    println!("{:?}", entry.file_name());
                    let ft = entry.file_type()?;
                    let mut new_path = None;
                    if ft.is_dir() {
                        new_path = Some(path.push(Part::Folder {
                            name: entry.file_name(),
                        }));
                    } else if ft.is_file() {
                        new_path = Some(path.push(Part::File {
                            name: entry.file_name(),
                        }));
                    }
                    if let Some(new_path) = new_path {
                        nodes.push(Node::new(new_path));
                    }
                }
            }
            FsPath::File(file) => {}
        }

        Ok(nodes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list() -> util::Result<()> {
        let mut tree = Tree::new();
        let path = Path::root();
        println!("{}", path);
        let nodes = tree.list(&path)?;
        for node in &nodes {
            println!("{}", node.path);
        }
        Ok(())
    }
}
