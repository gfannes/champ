use crate::error;

#[derive(Default, Clone)]
pub struct Path {
    pub parts: Vec<String>,
}

impl Path {
    pub fn new() -> Path {
        Default::default()
    }

    pub fn add(&mut self, part: &str) -> &mut Self {
        self.parts.push(part.to_string());
        self
    }
}

impl std::convert::From<std::path::PathBuf> for Path {
    fn from(other: std::path::PathBuf) -> Path {
        let mut path = Path::new();
        for part in other.components() {
            match part {
                std::path::Component::Normal(str) => {
                    path.parts.push(str.to_string_lossy().to_string())
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
