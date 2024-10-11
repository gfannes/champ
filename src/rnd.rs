use crate::{fail, util};
use std::collections;

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Debug, Default)]
pub struct Key(String);

#[derive(Default)]
pub struct KeySet(collections::BTreeSet<Key>);

#[derive(PartialEq, Eq, Debug)]
pub enum Kind {
    Absolute,
    Relative,
    Tag,
}

impl From<&str> for Kind {
    fn from(s: &str) -> Self {
        if s.starts_with("//") {
            Kind::Absolute
        } else if s.starts_with("/") {
            Kind::Relative
        } else {
            Kind::Tag
        }
    }
}

impl Key {
    pub fn new(s: impl Into<String>) -> Key {
        Key(s.into())
    }

    pub fn join(&self, child: &Key) -> Option<Key> {
        match (self.kind(), child.kind()) {
            (_, Kind::Absolute) => Some(child.clone()),
            (Kind::Absolute, Kind::Relative) => Some(Key::new(format!("{}{}", self, child))),
            _ => None,
        }
    }

    pub fn kind(&self) -> Kind {
        self.0.as_str().into()
    }
}

impl KeySet {
    pub fn new() -> KeySet {
        KeySet::default()
    }

    pub fn insert(&mut self, key: Key) -> util::Result<()> {
        if key.kind() != Kind::Absolute {
            fail!("Only Absolute key can be added to a KeySet");
        }
        self.0.insert(key);
        Ok(())
    }

    pub fn find(&self, needle: &Key) -> util::Result<Key> {
        let mut found_key = None;
        {
            let needle_kind = needle.kind();
            for k in &self.0 {
                match k.kind() {
                    Kind::Absolute => {
                        let is_match = match needle_kind {
                            Kind::Absolute => k.0.as_str() == needle.0.as_str(),
                            Kind::Tag => k.0.contains(needle.0.as_str()),
                            _ => false,
                        };

                        if is_match {
                            if let Some(found_key) = &found_key {
                                fail!(
                                "Found more than one match for '{needle}': '{found_key}' and '{k}'"
                            )
                            }
                            found_key = Some(k.clone());
                        }
                    }
                    _ => fail!("Unexpected kind {} in KeySet", k.kind()),
                }
            }
        }

        found_key.ok_or_else(|| util::Error::create("Could not find key"))
    }
}

impl std::fmt::Display for Key {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", &self.0)
    }
}

impl std::fmt::Display for KeySet {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        for key in &self.0 {
            write!(f, " {key}")?;
        }
        Ok(())
    }
}

impl std::fmt::Display for Kind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            Kind::Absolute => "Absolute",
            Kind::Relative => "Relative",
            Kind::Tag => "Tag",
        };
        write!(f, "{s}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_join() {
        let scns = [
            ("//abc", "/def", "//abc/def"),
            ("abc", "//def", "//def"),
            ("/abc", "//def", "//def"),
            ("//abc", "//def", "//def"),
        ];
        for (parent, child, exp) in scns {
            let parent = Key::new(parent);
            let child = Key::new(child);
            match parent.join(&child) {
                Some(join) => assert_eq!(join, Key::new(exp)),
                _ => assert!(false),
            }
        }
    }

    #[test]
    fn test_keyset_find() -> util::Result<()> {
        let scns = [
            ("//abc", "//abc", "//abc"),
            ("//abc/def", "c/d", "//abc/def"),
            (
                "//abc/def //todo //todo //abc/def //todo",
                "def",
                "//abc/def",
            ),
        ];
        for (keyset_str, needle_str, exp_str) in scns {
            let mut keyset = KeySet::new();
            for part in keyset_str.split(' ') {
                keyset.insert(Key::new(part))?;
            }
            let needle = Key::new(needle_str);
            match keyset.find(&needle) {
                Ok(found) => assert_eq!(found, Key::new(exp_str)),
                _ => assert!(false),
            }
        }
        Ok(())
    }

    #[test]
    fn test_key_kind() {
        let scns = [
            ("//abc", &Kind::Absolute),
            ("/abc", &Kind::Relative),
            ("abc", &Kind::Tag),
        ];
        for (s, kind) in scns {
            let key = Key::new(s);
            assert_eq!(&key.kind(), kind);
        }
    }
}
