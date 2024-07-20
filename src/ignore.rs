use crate::{fail, path, util};
use std::collections;

#[derive(Debug)]
pub struct Filter<'a> {
    matcher: &'a ignore::gitignore::Gitignore,
}
impl<'a> Filter<'a> {
    fn new(matcher: &ignore::gitignore::Gitignore) -> Filter {
        Filter { matcher }
    }
    pub fn call(&self, path: &path::Path) -> bool {
        let m = self.matcher.matched(path.path_buf(), path.is_folder());
        match m {
            ignore::Match::Ignore(..) => return false,
            _ => return true,
        }
    }
}

#[derive(Debug)]
struct Node {
    builder: ignore::gitignore::GitignoreBuilder,
    matcher: ignore::gitignore::Gitignore,
}

#[derive(Default)]
pub struct Tree {
    tree: collections::BTreeMap<path::Path, Node>,
}

// Pops parts from path until we either find a .gitignore file, or are at the root
fn trim_to_ignore(path: &mut path::Path) {
    path.keep_folder();

    loop {
        let found_gitignore;
        {
            path.push(path::Part::File {
                name: ".gitignore".into(),
            });
            found_gitignore = path.exist();
            path.pop();
        }

        if found_gitignore {
            return;
        }

        if path.is_empty() {
            return;
        }
        path.pop();
    }
}

impl Tree {
    pub fn new() -> Tree {
        Tree::default()
    }
    pub fn with_matcher(
        &mut self,
        mut path: path::Path,
        cb: impl Fn(&Filter) -> util::Result<()>,
    ) -> util::Result<()> {
        trim_to_ignore(&mut path);

        self.prepare(&path)?;

        if let Some(node) = self.tree.get(&path) {
            let filter = Filter::new(&node.matcher);
            cb(&filter)?;
        } else {
            unreachable!();
        }

        Ok(())
    }

    fn prepare(&mut self, path: &path::Path) -> util::Result<()> {
        if !self.tree.contains_key(&path) {
            if path.is_empty() {
                // Insert new node at root level
                let builder = ignore::gitignore::GitignoreBuilder::new("/");
                let matcher = builder.build()?;
                self.tree.insert(path.clone(), Node { builder, matcher });
            } else {
                let mut parent = path.clone();
                parent.pop();
                trim_to_ignore(&mut parent);

                self.prepare(&parent)?;

                if let Some(parent_node) = self.tree.get(&parent) {
                    let mut builder = parent_node.builder.clone();
                    let gitignore_path = path
                        .push_clone(path::Part::File {
                            name: ".gitignore".into(),
                        })
                        .path_buf();
                    builder.add(gitignore_path);
                    let matcher = builder.build()?;
                    self.tree.insert(path.clone(), Node { builder, matcher });
                }
            }
        }
        Ok(())
    }

    fn goc(
        &mut self,
        path: &mut path::Path,
        cb: impl FnOnce(&Node) -> util::Result<()>,
    ) -> util::Result<()> {
        while !path.is_empty() {
            if let Some(node) = self.tree.get(path) {
                // Found existing node
                return cb(node);
            }

            let found_gitignore;
            {
                path.push(path::Part::File {
                    name: ".gitignore".into(),
                });
                found_gitignore = path.exist();
                path.pop();
            }

            if found_gitignore {
                if let Some(part) = path.pop() {
                    let orig_path = path.push_clone(part);

                    // Create new node
                    let mut node = None;
                    let my_cb = |parent: &Node| {
                        let mut builder = parent.builder.clone();
                        builder.add(orig_path.path_buf());
                        let matcher = builder.build()?;
                        node = Some(Node { builder, matcher });
                        Ok(())
                    };
                    self.goc(path, my_cb)?;

                    // Insert new node
                    if let Some(node) = node {
                        self.tree.insert(orig_path, node);
                    }

                    // Retrieve new node
                    if let Some(node) = self.tree.get(path) {
                        // Found existing node
                        return cb(node);
                    }
                } else {
                    unreachable!();
                }
            }
        }

        // Retrieve root level node
        if let Some(node) = self.tree.get(path) {
            return cb(node);
        }
        unreachable!();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tree() -> util::Result<()> {
        let mut tree = Tree::new();
        let mut path = path::Path::current()?;
        if let path::FsPath::Folder(cwd) = path.fs_path()? {
            let cb = |filter: &Filter| {
                for entry in std::fs::read_dir(&cwd)? {
                    let entry = entry?;
                    let path;
                    if entry.file_type()?.is_file() {
                        path = path::Path::file(entry.path());
                    } else {
                        path = path::Path::folder(entry.path());
                    }
                    println!("path: {:?}, filter: {}", &path, filter.call(&path));
                }
                Ok(())
            };
            tree.with_matcher(path, cb)?;
        }
        Ok(())
    }
}
