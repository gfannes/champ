use crate::my;

pub struct Mgr {
    pub current_ix: usize,
    paths: Vec<Path>,
}

impl Mgr {
    pub fn new() -> my::Result<Mgr> {
        let mut res = Mgr {
            paths: Vec::new(),
            current_ix: 0,
        };

        res.switch_tab(0)?;

        Ok(res)
    }

    pub fn current(&self) -> &Path {
        &self.paths[self.current_ix]
    }

    pub fn set_current(&mut self, path: Path) {
        self.paths[self.current_ix] = path;
    }

    pub fn switch_tab(&mut self, tab: usize) -> my::Result<()> {
        while self.paths.len() <= tab {
            self.paths.push(Path::from(std::env::current_dir()?));
        }
        self.current_ix = tab;
        Ok(())
    }
}

#[derive(Default, Clone, PartialEq, Eq, Hash)]
pub struct Path {
    parts: Vec<String>,
}

impl Path {
    pub fn new() -> Path {
        Default::default()
    }

    pub fn push(&mut self, part: impl Into<String>) -> &mut Self {
        self.parts.push(part.into());
        self
    }
    pub fn pop(&mut self) -> Option<String> {
        self.parts.pop()
    }
}

impl std::convert::From<std::path::PathBuf> for Path {
    fn from(other: std::path::PathBuf) -> Path {
        let mut path = Path::new();
        for part in other.components() {
            match part {
                std::path::Component::Normal(str) => {
                    path.push(str.to_string_lossy());
                }
                _ => {}
            }
        }
        path
    }
}

impl std::convert::From<&Path> for std::path::PathBuf {
    fn from(other: &Path) -> std::path::PathBuf {
        let mut pb = std::path::PathBuf::new();
        pb.push("/");
        for part in &other.parts {
            pb.push(part);
        }
        pb
    }
}

// impl std::convert::Into<std::path::PathBuf> for Path {
//     fn into(self) -> std::path::PathBuf {
//         let mut pb = std::path::PathBuf::new();
//         pb.push("/");
//         for part in self.parts {
//             pb.push(part);
//         }
//         pb
//     }
// }

impl std::fmt::Display for Path {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.parts.is_empty() {
            write!(f, "/")?;
        } else {
            for part in &self.parts {
                write!(f, "/{}", part)?;
            }
        }
        Ok(())
    }
}

#[test]
fn test_new_push() {
    let mut p = Path::new();
    assert_eq!(format!("{}", p), "/");
    p.push("abc");
    assert_eq!(format!("{}", p), "/abc");
    p.push("def".to_string());
    assert_eq!(format!("{}", p), "/abc/def");
}
