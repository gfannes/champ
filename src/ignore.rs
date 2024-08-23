use crate::{path, util};
use std::collections;

// Filter.call() returns true for files that should be considered.

#[derive(Debug)]
pub struct Filter<'a> {
    tree: &'a Tree,
    ix: Option<usize>,
}
impl<'a> Filter<'a> {
    fn new(tree: &Tree, ix: Option<usize>) -> Filter {
        Filter { tree, ix }
    }
    pub fn call(&self, path: &path::Path) -> bool {
        // println!("ignore.Filter.call({}) base: {}", &path, &self.base);
        if path.is_hidden() {
            return false;
        }

        let mut ix_opt = self.ix;
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

impl Tree {
    pub fn new() -> Tree {
        Tree::default()
    }

    // Calls cb with a Filter for the given path. A callback is used to avoid copying the gitignore matchers.
    pub fn with_filter(
        &mut self,
        path: &path::Path,
        mut cb: impl FnMut(&Filter) -> util::Result<()>,
    ) -> util::Result<()> {
        // println!("ignore.Tree.with_filter({})", path);

        let ix = self.goc_matcher_ix(path)?;
        let filter = Filter::new(self, ix);
        cb(&filter)?;

        Ok(())
    }

    fn goc_matcher_ix(&mut self, path: &path::Path) -> util::Result<Option<usize>> {
        let mut res: Option<usize> = None;
        let mut prev_ix: Option<usize> = None;

        let mut path = path.clone();
        path.keep_folder();

        while !path.is_empty() {
            let found_gitignore;
            {
                path.push(path::Part::File {
                    name: ".gitignore".into(),
                });
                found_gitignore = path.exist();
                path.pop();
            }

            if found_gitignore {
                if let Some(ix) = self.map.get(&path) {
                    // We found path in our map: we can stop searching

                    // Fill-in the parent_ix for prev_ix, if present
                    if let Some(prev_ix) = prev_ix {
                        self.matchers[prev_ix].parent_ix = Some(*ix);
                    }
                    // Setup res, if this is the first time
                    if res.is_none() {
                        res = Some(*ix);
                    }
                    return Ok(res);
                } else {
                    // We did not find path in our map: add it and continue the search

                    let mut builder = ignore::gitignore::GitignoreBuilder::new(path.path_buf());
                    let gitignore_path = path
                        .push_clone(path::Part::File {
                            name: ".gitignore".into(),
                        })
                        .path_buf();
                    builder.add(gitignore_path);

                    let ix = self.matchers.len();
                    self.map.insert(path.clone(), ix);
                    self.matchers.push(Matcher {
                        gitignore: builder.build()?,
                        base: path.clone(),
                        // We do not know the parent_ix yet, this will be filled-in later based on prev_ix
                        parent_ix: None,
                    });

                    // Fill-in the parent_ix for prev_ix, if present
                    if let Some(prev_ix) = prev_ix {
                        self.matchers[prev_ix].parent_ix = Some(ix);
                    }
                    // Store ix as prev_ix to store its parent_ix later
                    prev_ix = Some(ix);

                    // Setup res, if this is the first time
                    if res.is_none() {
                        res = Some(ix);
                    }
                }
            }

            let found_git;
            {
                path.push(path::Part::File {
                    name: ".git".into(),
                });
                found_git = path.exist();
                path.pop();
            }

            if found_git {
                // When we find a .git file/folder, we stop searching and don't fill-in any parent_ix: nested git repo's do not inherit their .gitignore rules.
                return Ok(res);
            }

            path.pop();
        }

        if let Some(ix) = self.map.get(&path) {
            // We found the empty path in our map

            // Fill-in the parent_ix for prev_ix, if present
            if let Some(prev_ix) = prev_ix {
                self.matchers[prev_ix].parent_ix = Some(*ix);
            }
            // Setup res, if this is the first time
            if res.is_none() {
                res = Some(*ix);
            }
        } else {
            // We did not find the empty path in our map: insert it

            let builder = ignore::gitignore::GitignoreBuilder::new("/");

            let ix = self.matchers.len();
            self.map.insert(path.clone(), ix);
            self.matchers.push(Matcher {
                gitignore: builder.build()?,
                base: path.clone(),
                parent_ix: None,
            });

            // Fill-in the parent_ix for prev_ix, if present
            if let Some(prev_ix) = prev_ix {
                self.matchers[prev_ix].parent_ix = Some(ix);
            }
            // Setup res, if this is the first time
            if res.is_none() {
                res = Some(ix);
            }
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
            tree.with_filter(&path, cb)?;
        }
        Ok(())
    }
}
