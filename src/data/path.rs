#[derive(Default, Clone)]
pub struct Path {
    pub parts: Vec<String>,
}

impl Path {
    pub fn new() -> Path {
        Default::default()
    }

    pub fn add(&mut self, part: impl Into<String>) -> &mut Self {
        self.parts.push(part.into());
        self
    }
}

impl std::convert::From<std::path::PathBuf> for Path {
    fn from(other: std::path::PathBuf) -> Path {
        let mut path = Path::new();
        for part in other.components() {
            match part {
                std::path::Component::Normal(str) => {
                    path.add(str.to_string_lossy());
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
fn test_new_add() {
    let mut p = Path::new();
    assert_eq!(format!("{}", p), "/");
    p.add("abc");
    assert_eq!(format!("{}", p), "/abc");
    p.add("def".to_string());
    assert_eq!(format!("{}", p), "/abc/def");
}
