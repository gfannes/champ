// Annotation Metadata Protocol

use crate::{config, ignore, path, util};
use std::{ffi, fs};

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

#[derive(Debug)]
pub struct ForestSpec {
    base: path::Path,
    pub hidden: bool,
    pub ignore: bool,
    // We assume a limited amount of extensions (less than 64): linear search is faster than using a BTreeSet
    pub include: Vec<ffi::OsString>,
    pub max_size: Option<usize>,
}
impl ForestSpec {
    fn call(&self, path: &path::Path) -> bool {
        let includes_base = self.base.include(path) || path.include(&self.base);
        if !includes_base {
            return false;
        }
        if self.include.is_empty() {
            // No extensions were specified
            return true;
        }
        if let Some(ext) = path.extension() {
            self.include.iter().position(|e| e == ext).is_some()
        } else {
            // path has no extension: we only continue when it is a folder
            path.is_folder()
        }
    }
}
impl From<&config::Forest> for ForestSpec {
    fn from(config_forest: &config::Forest) -> ForestSpec {
        ForestSpec {
            base: path::Path::folder(&config_forest.path),
            hidden: config_forest.hidden,
            ignore: config_forest.ignore,
            include: config_forest
                .include
                .iter()
                .map(ffi::OsString::from)
                .collect(),
            max_size: config_forest.max_size,
        }
    }
}

pub struct Forest {
    spec: ForestSpec,
    ignore_tree: ignore::Tree,
}

impl Forest {
    pub fn new() -> Forest {
        Forest {
            spec: ForestSpec {
                base: path::Path::root(),
                hidden: false,
                ignore: false,
                include: Vec::new(),
                max_size: None,
            },
            ignore_tree: ignore::Tree::new(),
        }
    }
    pub fn set_forest(&mut self, forest_spec: ForestSpec) {
        println!("amp.Forest.set_forest({})", &forest_spec.base);
        self.spec = forest_spec;
    }
    pub fn max_size(&self) -> Option<usize> {
        self.spec.max_size
    }
    pub fn list(&mut self, path: &path::Path) -> util::Result<Vec<path::Path>> {
        // println!("\namp.Forest.list({})", &path);

        let mut paths = Vec::new();

        if path.is_folder() {
            self.ignore_tree
                .with_filter(path, |filter: &ignore::Filter| {
                    // Process each file/folder in path
                    for entry in std::fs::read_dir(&path.path_buf())? {
                        let entry = entry?;
                        if let Ok(file_type) = entry.file_type() {
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
                                // Something else
                                new_path = None;
                            }

                            if let Some(new_path) = new_path {
                                if filter.call(&new_path) && self.spec.call(&new_path) {
                                    paths.push(new_path);
                                }
                            }
                        }
                    }
                    Ok(())
                })?;
        }

        Ok(paths)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list() -> util::Result<()> {
        let mut forest = Forest::new();
        forest.set_forest(ForestSpec {
            base: path::Path::folder("/home/geertf"),
            hidden: true,
            ignore: true,
            include: Vec::new(),
            max_size: None,
        });
        let path = path::Path::folder("/home/geertf");
        let paths = forest.list(&path)?;
        for p in &paths {
            println!("{}", p);
        }
        Ok(())
    }
}
