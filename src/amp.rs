// Annotation Metadata Protocol

use crate::{config, fail, util};
use std::{ffi, fmt, fs, path};

#[derive(Clone, PartialEq)]
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
    pub fn folder(path: impl AsRef<path::Path>) -> Path {
        let mut p = Path::root();
        for component in path.as_ref().components() {
            let component = component.as_os_str();
            if component != "/" {
                p = p.push(Part::Folder {
                    name: component.into(),
                });
            }
        }
        p
    }
    fn include(&self, rhs: &Path) -> bool {
        let parts_to_check = rhs.parts.len();
        if self.parts.len() < parts_to_check {
            return false;
        }
        for ix in 0..parts_to_check {
            if rhs.parts[ix] != self.parts[ix] {
                return false;
            }
        }
        true
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

pub struct Filter {
    base: Path,
}
impl Filter {
    fn new(base: Path) -> Filter {
        Filter { base }
    }
    fn call(&self, path: &Path) -> bool {
        self.base.include(path) || path.include(&self.base)
    }
}
impl From<&config::Filter> for Filter {
    fn from(filter: &config::Filter) -> Filter {
        Filter {
            base: Path::folder(&filter.path),
        }
    }
}

pub struct Tree {
    filter: Filter,
}

impl Tree {
    pub fn new() -> Tree {
        Tree {
            filter: Filter::new(Path::root()),
        }
    }
    pub fn set_filter(&mut self, filter: Filter) {
        self.filter = filter;
    }
    pub fn list(&mut self, path: &Path) -> util::Result<Vec<Path>> {
        let mut paths = Vec::new();

        match path.fs_path()? {
            FsPath::Folder(folder) => {
                for entry in fs::read_dir(&folder)? {
                    let entry = entry?;

                    let mut new_path = None;

                    let ft = entry.file_type()?;
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
                        if self.filter.call(&new_path) {
                            paths.push(new_path);
                        }
                    }
                }
            }
            FsPath::File(_file) => {}
        }

        Ok(paths)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list() -> util::Result<()> {
        let mut tree = Tree::new();
        tree.set_filter(Filter::new(Path::folder("/home/geertf")));
        let path = Path::folder("/home/geertf");
        let paths = tree.list(&path)?;
        for p in &paths {
            println!("{}", p);
        }
        Ok(())
    }
}
