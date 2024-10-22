// Annotation Metadata Protocol

use crate::{config, fail, ignore, path, util};
use std::{ffi, fs};
use tracing::{info, trace, warn};

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
pub struct GroveSpec {
    base: path::Path,
    // &todo: Enable removal of hidden files/folders
    pub hidden: bool,
    // &todo: Enable removal of ignored files/folders
    pub ignore: bool,
    // We assume a limited amount of extensions (less than 64): linear search is faster than using a BTreeSet
    pub include: Vec<ffi::OsString>,
    // &todo: Enable removal of large files
    pub max_size: Option<usize>,
}

impl GroveSpec {
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

impl From<&config::Grove> for GroveSpec {
    fn from(config_grove: &config::Grove) -> GroveSpec {
        GroveSpec {
            base: path::Path::folder(&config_grove.path),
            hidden: config_grove.hidden,
            ignore: config_grove.ignore,
            include: config_grove
                .include
                .iter()
                .map(ffi::OsString::from)
                .collect(),
            max_size: config_grove.max_size,
        }
    }
}

pub struct Forest {
    specs: Vec<GroveSpec>,
    ignore_tree: ignore::Tree,
}

impl Forest {
    pub fn new() -> Forest {
        Forest {
            specs: Vec::new(),
            ignore_tree: ignore::Tree::new(),
        }
    }

    pub fn add_grove(&mut self, forest_spec: GroveSpec) {
        info!("amp.Forest.set_forest({})", &forest_spec.base);
        self.specs.push(forest_spec);
    }

    pub fn list(&mut self, path: &path::Path) -> util::Result<Vec<path::Path>> {
        trace!("amp.Forest.list({})", &path);

        let mut paths = Vec::new();

        if path.is_folder() {
            self.ignore_tree
                .with_filter(path, |filter: &ignore::Filter| {
                    let mut entries =
                        std::fs::read_dir(&path.path_buf())?.collect::<Result<Vec<_>, _>>()?;
                    entries.sort_by(|a, b| a.file_name().cmp(&b.file_name()));

                    // Process each file/folder in path
                    for entry in entries {
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
                                        warn!(
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
                                warn!("I cannot handle '{}'", entry.file_name().to_string_lossy());
                                // Something else
                                new_path = None;
                            }

                            if let Some(new_path) = new_path {
                                if filter.call(&new_path)
                                    && self.specs.iter().any(|spec| spec.call(&new_path))
                                {
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

pub fn expand_path(path: &std::path::Path) -> util::Result<std::path::PathBuf> {
    let mut res = std::path::PathBuf::new();
    let mut first = true;
    for component in path.components() {
        trace!("component: {:?}", &component);
        match component {
            std::path::Component::Prefix(prefix) => {
                res.push(prefix.as_os_str());
                first = false;
            }
            std::path::Component::RootDir => {
                res.push("/");
                first = false;
            }
            std::path::Component::CurDir => {
                if first {
                    res.push(std::env::current_dir()?);
                    first = false;
                }
            }
            std::path::Component::Normal(normal) => {
                if first {
                    res.push(std::env::current_dir()?);
                    first = false;
                }
                res.push(normal);
            }
            std::path::Component::ParentDir => {
                fail!("No support for '..' in root dir yet");
            }
        }
    }
    Ok(res)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list() -> util::Result<()> {
        let home_dir = std::env::var("HOME")?;

        let mut forest = Forest::new();
        forest.add_grove(GroveSpec {
            base: path::Path::folder(&home_dir),
            hidden: true,
            ignore: true,
            include: Vec::new(),
            max_size: None,
        });
        let path = path::Path::folder(&home_dir);
        let paths = forest.list(&path)?;
        for p in &paths {
            println!("{}", p);
        }
        Ok(())
    }
}
