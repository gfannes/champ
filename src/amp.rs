// Annotation Metadata Protocol

use crate::{config, path, util};
use std::fs;

pub struct Node {
    path: path::Path,
    name: String,
}
impl Node {
    fn new(path: path::Path) -> Node {
        Node {
            path,
            name: String::new(),
        }
    }
}

pub struct TreeSpec {
    base: path::Path,
    pub hidden: bool,
    pub ignore: bool,
}
impl TreeSpec {
    fn call(&self, path: &path::Path) -> bool {
        self.base.include(path) || path.include(&self.base)
    }
}
impl From<&config::Tree> for TreeSpec {
    fn from(config_tree: &config::Tree) -> TreeSpec {
        TreeSpec {
            base: path::Path::folder(&config_tree.path),
            hidden: config_tree.hidden,
            ignore: config_tree.ignore,
        }
    }
}

pub struct Tree {
    spec: TreeSpec,
}

impl Tree {
    pub fn new() -> Tree {
        Tree {
            spec: TreeSpec {
                base: path::Path::root(),
                hidden: false,
                ignore: false,
            },
        }
    }
    pub fn set_tree(&mut self, tree_spec: TreeSpec) {
        self.spec = tree_spec;
    }
    pub fn list(&mut self, path: &path::Path) -> util::Result<Vec<path::Path>> {
        let mut paths = Vec::new();

        match path.fs_path()? {
            path::FsPath::Folder(folder) => {
                // @perf: Creating a new Walk for every folder is a performance killer.
                // Better is to store the ignore::gitignore::Gitignore for folders that have a .gitignore, and reuse them.
                for entry in ignore::WalkBuilder::new(&folder)
                    .hidden(self.spec.hidden)
                    .ignore(self.spec.ignore)
                    .git_ignore(self.spec.ignore)
                    .max_depth(Some(1))
                    .build()
                    .skip(1)
                {
                    let entry = entry?;

                    if let Some(file_type) = entry.file_type() {
                        let new_path;

                        if file_type.is_dir() {
                            new_path = Some(path.push_clone(path::Part::Folder {
                                name: entry.file_name().into(),
                            }));
                        } else if file_type.is_file() {
                            new_path = Some(path.push_clone(path::Part::File {
                                name: entry.file_name().into(),
                            }));
                        } else if file_type.is_symlink() {
                            match fs::metadata(entry.path()) {
                                Err(err) => {
                                    println!(
                                        "Warning: Skipping {}, could not read metadata: {}",
                                        entry.path().display(),
                                        &err
                                    );
                                    new_path = None;
                                }
                                Ok(mut metadata) => {
                                    if metadata.is_symlink() {
                                        metadata = fs::symlink_metadata(entry.path())?;
                                    }
                                    if metadata.is_dir() {
                                        new_path = Some(path.push_clone(path::Part::Folder {
                                            name: entry.file_name().into(),
                                        }));
                                    } else if metadata.is_file() {
                                        new_path = Some(path.push_clone(path::Part::File {
                                            name: entry.file_name().into(),
                                        }));
                                    } else {
                                        new_path = None;
                                    }
                                }
                            }
                        } else {
                            new_path = None;
                        }

                        if let Some(new_path) = new_path {
                            if self.spec.call(&new_path) {
                                paths.push(new_path);
                            }
                        }
                    }
                }
            }
            path::FsPath::File(_file) => {}
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
        tree.set_tree(TreeSpec {
            base: path::Path::folder("/home/geertf"),
            hidden: true,
            ignore: true,
        });
        let path = path::Path::folder("/home/geertf");
        let paths = tree.list(&path)?;
        for p in &paths {
            println!("{}", p);
        }
        Ok(())
    }
}
