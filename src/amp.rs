// Annotation Metadata Protocol

use crate::{config, fail, util};
use std::{collections, ffi, fmt, fs, path};

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
    fn is_hidden(&self) -> bool {
        let is_hidden = |name: &ffi::OsString| {
            if let Some(ch) = name.to_string_lossy().chars().next() {
                if ch == '.' {
                    return true;
                }
            }
            false
        };
        for part in &self.parts {
            match part {
                Part::Folder { name } => {
                    if is_hidden(name) {
                        return true;
                    }
                }
                Part::File { name } => {
                    if is_hidden(name) {
                        return true;
                    }
                }
                _ => {}
            }
        }
        false
    }
    fn push(&self, part: Part) -> Path {
        let mut path = self.clone();
        path.parts.push(part);
        path
    }
    pub fn fs_path(&self) -> util::Result<FsPath> {
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
    pub fn keep_folder(&mut self) {
        while let Some(part) = self.parts.last() {
            match part {
                Part::Folder { .. } => {
                    break;
                }
                _ => {}
            }
        }
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

#[derive(Debug)]
pub enum FsPath {
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
    pub hidden: bool,
    pub ignore: bool,
}
impl Filter {
    fn call(&self, path: &Path) -> bool {
        self.base.include(path) || path.include(&self.base)
    }
}
impl From<&config::Filter> for Filter {
    fn from(filter: &config::Filter) -> Filter {
        Filter {
            base: Path::folder(&filter.path),
            hidden: filter.hidden,
            ignore: filter.ignore,
        }
    }
}

pub struct Tree {
    filter: Filter,
}

impl Tree {
    pub fn new() -> Tree {
        Tree {
            filter: Filter {
                base: Path::root(),
                hidden: false,
                ignore: false,
            },
        }
    }
    pub fn set_filter(&mut self, filter: Filter) {
        self.filter = filter;
    }
    pub fn list(&mut self, path: &Path) -> util::Result<Vec<Path>> {
        let mut paths = Vec::new();

        match path.fs_path()? {
            FsPath::Folder(folder) => {
                // @perf: Creating a new Walk for every folder is a performance killer.
                // Better is to store the ignore::gitignore::Gitignore for folders that have a .gitignore, and reuse them.
                for entry in ignore::WalkBuilder::new(&folder)
                    .hidden(self.filter.hidden)
                    .ignore(self.filter.ignore)
                    .git_ignore(self.filter.ignore)
                    .max_depth(Some(1))
                    .build()
                    .skip(1)
                {
                    let entry = entry?;

                    if let Some(file_type) = entry.file_type() {
                        let new_path;

                        if file_type.is_dir() {
                            new_path = Some(path.push(Part::Folder {
                                name: entry.file_name().into(),
                            }));
                        } else if file_type.is_file() {
                            new_path = Some(path.push(Part::File {
                                name: entry.file_name().into(),
                            }));
                        } else if file_type.is_symlink() {
                            let mut metadata = fs::metadata(entry.path())?;
                            if metadata.is_symlink() {
                                metadata = fs::symlink_metadata(entry.path())?;
                            }
                            if metadata.is_dir() {
                                new_path = Some(path.push(Part::Folder {
                                    name: entry.file_name().into(),
                                }));
                            } else if metadata.is_file() {
                                new_path = Some(path.push(Part::File {
                                    name: entry.file_name().into(),
                                }));
                            } else {
                                new_path = None;
                            }
                        } else {
                            new_path = None;
                        }

                        if let Some(new_path) = new_path {
                            if self.filter.call(&new_path) {
                                paths.push(new_path);
                            }
                        }
                    }

                    // match fs::metadata(entry.path()) {
                    //     Err(err) => {
                    //         println!(
                    //             "Error: could not read metadata for {}: {}",
                    //             entry.path().display(),
                    //             &err
                    //         );
                    //     }
                    //     Ok(mut metadata) => {
                    //         if metadata.is_symlink() {
                    //             metadata = fs::symlink_metadata(entry.path())?;
                    //         }

                    //         let new_path;
                    //         if metadata.is_dir() {
                    //             new_path = Some(path.push(Part::Folder {
                    //                 name: entry.file_name().into(),
                    //             }));
                    //         } else if metadata.is_file() {
                    //             new_path = Some(path.push(Part::File {
                    //                 name: entry.file_name().into(),
                    //             }));
                    //         } else {
                    //             new_path = None;
                    //         }

                    //         if let Some(new_path) = new_path {
                    //             if self.filter.call(&new_path) {
                    //                 paths.push(new_path);
                    //             }
                    //         }
                    //     }
                    // }
                }
            }
            FsPath::File(_file) => {}
        }

        Ok(paths)
    }
}

struct Gitignore {
    builder: ignore::gitignore::GitignoreBuilder,
    matcher: ignore::gitignore::Gitignore,
}

struct GitignoreTree {
    tree: collections::BTreeMap<Path, Gitignore>,
}
impl GitignoreTree {
    fn new() -> GitignoreTree {
        GitignoreTree {
            tree: Default::default(),
        }
    }
    fn with_matcher(
        &mut self,
        mut path: Path,
        cb: impl Fn(&ignore::gitignore::Gitignore) -> (),
    ) -> util::Result<()> {
        path.keep_folder();
        // @todo: Recursively insert a builder and matcher for path
        // Below is some test code
        let mut builder = ignore::gitignore::GitignoreBuilder::new("/");
        let matcher = builder.build()?;
        cb(&matcher);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list() -> util::Result<()> {
        let mut tree = Tree::new();
        tree.set_filter(Filter {
            base: Path::folder("/home/geertf"),
            hidden: true,
            ignore: true,
        });
        let path = Path::folder("/home/geertf");
        let paths = tree.list(&path)?;
        for p in &paths {
            println!("{}", p);
        }
        Ok(())
    }
}
