// #[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Debug, Default)]
// pub struct Key(String);

// #[derive(Default, Debug)]
// pub struct KeySet(collections::BTreeSet<Key>);

// #[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Debug)]
// pub enum Kind {
//     Normal,
//     Definition,
//     Extension,
// }

// impl Default for Kind {
//     fn default() -> Kind {
//         Kind::Normal
//     }
// }

// pub type Value = Option<String>;

// #[derive(Default, Debug)]
// pub struct KeyValues {
//     data: collections::BTreeMap<Key, Vec<String>>,
// }

// impl KeyValues {
//     pub fn new() -> KeyValues {
//         Default::default()
//     }

//     pub fn insert(&mut self, key: &Key, value: &Value) {
//         if !self.data.contains_key(key) {
//             self.data.insert(key.clone(), Vec::new());
//         }
//         if let Some(value) = value {
//             if let Some(values) = self.data.get_mut(key) {
//                 values.push(value.clone());
//             }
//         }
//     }
// }

// impl std::fmt::Display for KeyValues {
//     fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
//         for (k, vs) in &self.data {
//             write!(f, "{}->[", k)?;
//             for v in vs {
//                 write!(f, "{},", v)?;
//             }
//             write!(f, "]")?;
//         }
//         Ok(())
//     }
// }

// impl From<&str> for Kind {
//     fn from(s: &str) -> Self {
//         if s.starts_with("//") {
//             Kind::Definition
//         } else if s.starts_with("/") {
//             Kind::Extension
//         } else {
//             Kind::Normal
//         }
//     }
// }

// impl Key {
//     pub fn new(s: impl Into<String>) -> Key {
//         Key(s.into())
//     }

//     pub fn join(&self, child: &Key) -> Option<Key> {
//         match (self.kind(), child.kind()) {
//             (_, Kind::Definition) => Some(child.clone()),
//             (Kind::Definition, Kind::Extension) => Some(Key::new(format!("{}{}", self, child))),
//             _ => None,
//         }
//     }

//     pub fn kind(&self) -> Kind {
//         self.0.as_str().into()
//     }
// }

// impl KeySet {
//     pub fn new() -> KeySet {
//         KeySet::default()
//     }

//     pub fn insert(&mut self, key: Key) -> util::Result<()> {
//         if key.kind() != Kind::Definition {
//             fail!("Only Absolute key can be added to a KeySet");
//         }
//         self.0.insert(key);
//         Ok(())
//     }

//     pub fn find(&self, needle: &Key) -> util::Result<Key> {
//         let mut found_key = None;
//         {
//             let needle_kind = needle.kind();
//             for k in &self.0 {
//                 match k.kind() {
//                     Kind::Definition => {
//                         let is_match = match needle_kind {
//                             Kind::Definition => k.0.as_str() == needle.0.as_str(),
//                             Kind::Normal => k.0.contains(needle.0.as_str()),
//                             _ => false,
//                         };

//                         if is_match {
//                             if let Some(found_key) = &found_key {
//                                 fail!(
//                                 "Found more than one match for '{needle}': '{found_key}' and '{k}'"
//                             )
//                             }
//                             found_key = Some(k.clone());
//                         }
//                     }
//                     _ => fail!("Unexpected kind {} in KeySet", k.kind()),
//                 }
//             }
//         }

//         found_key.ok_or_else(|| util::Error::create("Could not find key"))
//     }
// }

// impl std::fmt::Display for Key {
//     fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
//         write!(f, "{}", &self.0)
//     }
// }

// impl std::fmt::Display for KeySet {
//     fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
//         for key in &self.0 {
//             write!(f, " {key}")?;
//         }
//         Ok(())
//     }
// }

// impl std::fmt::Display for Kind {
//     fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
//         let s = match self {
//             Kind::Definition => "Absolute",
//             Kind::Extension => "Relative",
//             Kind::Normal => "Tag",
//         };
//         write!(f, "{s}")
//     }
// }

// #[cfg(test)]
// mod tests {
//     use super::*;

//     #[test]
//     fn test_join() {
//         let scns = [
//             ("//abc", "/def", "//abc/def"),
//             ("abc", "//def", "//def"),
//             ("/abc", "//def", "//def"),
//             ("//abc", "//def", "//def"),
//         ];
//         for (parent, child, exp) in scns {
//             let parent = Key::new(parent);
//             let child = Key::new(child);
//             match parent.join(&child) {
//                 Some(join) => assert_eq!(join, Key::new(exp)),
//                 _ => assert!(false),
//             }
//         }
//     }

//     #[test]
//     fn test_keyset_find() -> util::Result<()> {
//         let scns = [
//             ("//abc", "//abc", "//abc"),
//             ("//abc/def", "c/d", "//abc/def"),
//             (
//                 "//abc/def //todo //todo //abc/def //todo",
//                 "def",
//                 "//abc/def",
//             ),
//         ];
//         for (keyset_str, needle_str, exp_str) in scns {
//             let mut keyset = KeySet::new();
//             for part in keyset_str.split(' ') {
//                 keyset.insert(Key::new(part))?;
//             }
//             let needle = Key::new(needle_str);
//             match keyset.find(&needle) {
//                 Ok(found) => assert_eq!(found, Key::new(exp_str)),
//                 _ => assert!(false),
//             }
//         }
//         Ok(())
//     }

//     #[test]
//     fn test_key_kind() {
//         let scns = [
//             ("//abc", &Kind::Definition),
//             ("/abc", &Kind::Extension),
//             ("abc", &Kind::Normal),
//         ];
//         for (s, kind) in scns {
//             let key = Key::new(s);
//             assert_eq!(&key.kind(), kind);
//         }
//     }

//     #[test]
//     fn test_parse_path() {
//         let scns = [
//             ("!:defabs", Path::new(true, true, vec!["defabs"])),
//             ("!defrel", Path::new(true, false, vec!["defrel"])),
//             (":abs", Path::new(false, true, vec!["abs"])),
//             (":abs:abc", Path::new(false, true, vec!["abs", "abc"])),
//             ("rel", Path::new(false, false, vec!["rel"])),
//             ("rel:abc", Path::new(false, false, vec!["rel", "abc"])),
//         ];

//         for (content, exp) in scns {
//             if let Ok(path) = Path::try_from(content) {
//                 assert_eq!(&path, &exp);
//             } else {
//                 assert!(false)
//             }
//         }
//     }
// }
