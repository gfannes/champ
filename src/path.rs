use crate::{fail, util};
use std::{ffi, fmt, path};

#[derive(Clone, PartialEq, PartialOrd, Ord, Eq, Debug)]
pub enum Part {
    Folder { name: ffi::OsString },
    File { name: ffi::OsString },
    Range { begin: usize, size: usize },
}

#[derive(Clone, PartialOrd, PartialEq, Ord, Eq, Debug)]
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
                p = p.push_clone(Part::Folder {
                    name: component.into(),
                });
            }
        }
        p
    }
    pub fn file(path: impl AsRef<path::Path>) -> Path {
        let mut p = Path::folder(path);
        // Replace the last part into Part::File
        if let Some(part) = p.parts.pop() {
            if let Part::Folder { name } = part {
                p.parts.push(Part::File { name });
            }
        }
        p
    }
    pub fn current() -> util::Result<Path> {
        Ok(Path::folder(std::env::current_dir()?))
    }

    pub fn include(&self, rhs: &Path) -> bool {
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
    pub fn is_hidden(&self) -> bool {
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
    pub fn is_empty(&self) -> bool {
        self.parts.is_empty()
    }
    pub fn is_folder(&self) -> bool {
        for part in &self.parts {
            match part {
                Part::Folder { .. } => {}
                Part::File { .. } => return false,
                _ => {}
            }
        }
        true
    }
    pub fn is_file(&self) -> bool {
        !self.is_folder()
    }
    pub fn push(&mut self, part: Part) {
        self.parts.push(part);
    }
    pub fn pop(&mut self) -> Option<Part> {
        self.parts.pop()
    }
    pub fn push_clone(&self, part: Part) -> Path {
        let mut path = self.clone();
        path.push(part);
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
    pub fn path_buf(&self) -> std::path::PathBuf {
        let mut res = std::path::PathBuf::new();
        res.push("/");
        for part in &self.parts {
            match part {
                Part::Folder { name } => res.push(name),
                Part::File { name } => res.push(name),
                _ => {}
            }
        }
        res
    }
    pub fn relative_from(&self, base: &Path) -> std::path::PathBuf {
        let mut start_ix = Some(0);
        for (ix, part) in base.parts.iter().enumerate() {
            if ix >= self.parts.len() || &self.parts[ix] != part {
                start_ix = None;
                break;
            }
            start_ix = Some(ix);
        }
        if let Some(start_ix) = start_ix {
            let mut rel = std::path::PathBuf::new();
            for ix in start_ix + 1..self.parts.len() {
                if ix < self.parts.len() {
                    let part = &self.parts[ix];
                    match part {
                        Part::Folder { name } => rel.push(name),
                        Part::File { name } => rel.push(name),
                        Part::Range { .. } => break,
                    }
                }
            }
            rel
        } else {
            self.path_buf()
        }
    }
    pub fn exist(&self) -> bool {
        if let Ok(fs_path) = self.fs_path() {
            let path;
            match fs_path {
                FsPath::File(p) => path = p,
                FsPath::Folder(p) => path = p,
            }
            return std::fs::metadata(path).is_ok();
        }
        false
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_path_buf() {
        let mut path = Path::root();
        assert_eq!(path.path_buf(), std::path::PathBuf::from("/"));
        path.push(Part::Folder {
            name: "base".into(),
        });
        assert_eq!(path.path_buf(), std::path::PathBuf::from("/base"));
    }

    #[test]
    fn test_relative() {
        let base = Path::folder("/base");
        let file = Path::file("/base/rel/name.txt");
        assert_eq!(
            file.relative_from(&base),
            std::path::PathBuf::from("rel/name.txt")
        );
    }
}
