use crate::{path, util};
use std::collections;

// Filter.call() returns true for files that should be considered.

#[derive(Debug)]
pub struct Filter<'a> {
    tree: &'a Tree,
    ix: usize,
}
impl<'a> Filter<'a> {
    fn new(tree: &Tree, ix: usize) -> Filter {
        Filter { tree, ix }
    }
    pub fn call(&self, path: &path::Path) -> bool {
        // println!("ignore.Filter.call({}) base: {}", &path, &self.base);
        if path.is_hidden() {
            return false;
        }

        let mut ix_opt = Some(self.ix);
        while let Some(ix) = ix_opt {
            let matcher = &self.tree.matchers[ix];
            let rel = path.relative_from(&matcher.base);
            let m = matcher.gitignore.matched(&rel, path.is_folder());
            // println!("  rel {}, m: {:?}", rel.display(), &m);
            if let ignore::Match::Ignore(..) = m {
                // We found a matcher that ignores this file: stop searching and indicate this file should not be used.
                return false;
            } else {
                ix_opt = matcher.parent_ix;
            }
        }

        true
    }
}

// Tree keeps track of all the .gitignore files already loaded.
#[derive(Default, Debug)]
pub struct Tree {
    map: collections::BTreeMap<path::Path, usize>,
    matchers: Vec<Matcher>,
}

#[derive(Debug)]
struct Matcher {
    gitignore: ignore::gitignore::Gitignore,
    // Folder of the .gitignore file
    base: path::Path,
    // Points to the first Matcher towards the root
    parent_ix: Option<usize>,
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
            // println!("Found .gitignore {}", &path);
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

    // Calls cb with a Filter for the given path. A callback is used to avoid copying the gitignore matchers.
    pub fn with_filter(
        &mut self,
        mut path: path::Path,
        mut cb: impl FnMut(&Filter) -> util::Result<()>,
    ) -> util::Result<()> {
        // println!("ignore.Tree.with_filter({})", path);

        trim_to_ignore(&mut path);

        self.prepare(&path)?;

        if let Some(ix) = self.map.get(&path) {
            let filter = Filter::new(self, *ix);
            cb(&filter)?;
        } else {
            unreachable!();
        }

        Ok(())
    }

    fn prepare(&mut self, path: &path::Path) -> util::Result<usize> {
        let res: usize;
        if let Some(ix) = self.map.get(&path) {
            res = *ix;
        } else {
            let mut builder;
            let parent_ix;
            if path.is_empty() {
                // Insert new node at root level
                builder = ignore::gitignore::GitignoreBuilder::new("/");
                parent_ix = None;
            } else {
                // prepare() the parent, if needed
                {
                    let mut parent = path.clone();
                    parent.pop();
                    trim_to_ignore(&mut parent);
                    parent_ix = Some(self.prepare(&parent)?);
                }

                builder = ignore::gitignore::GitignoreBuilder::new(path.path_buf());
                let gitignore_path = path
                    .push_clone(path::Part::File {
                        name: ".gitignore".into(),
                    })
                    .path_buf();
                builder.add(gitignore_path);
            }

            res = self.matchers.len();
            self.map.insert(path.clone(), res);
            self.matchers.push(Matcher {
                gitignore: builder.build()?,
                base: path.clone(),
                parent_ix,
            });
        }
        Ok(res)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tree() -> util::Result<()> {
        let mut tree = Tree::new();
        let path = path::Path::current()?;
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
            tree.with_filter(path, cb)?;
        }
        Ok(())
    }
}
