pub mod parse;
pub mod value;

use crate::{
    rubr::{naft, strange},
    util,
};
use std::{collections, fmt::Display, fmt::Write};
use tracing::{trace, warn};

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Debug, Default)]
pub struct Path {
    pub is_definition: bool,
    pub is_absolute: bool,
    pub parts: Vec<Part>,
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Debug, Default)]
pub struct Paths {
    pub data: Vec<Path>,
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub enum Part {
    Text(String),
    Date(Date),
    Duration(Duration),
    Prio(Prio),
}

#[derive(PartialEq, Eq, Debug, Clone, Default, PartialOrd, Ord)]
pub struct Date {
    year: u16,
    month: u8,
    day: u8,
}

#[derive(PartialEq, Eq, Debug, Clone, Default, PartialOrd, Ord)]
pub struct Duration {
    minutes: u32,
}

#[derive(PartialEq, Eq, Debug, Clone, Default, PartialOrd, Ord)]
pub struct Prio {
    pub major: u32,
    pub minor: u32,
}

impl Duration {
    pub fn new(weeks: u32, days: u32, hours: u32, minutes: u32) -> Duration {
        let minutes = minutes + (hours + (days + weeks * 5) * 8) * 60;
        Duration { minutes }
    }
}

impl Date {
    pub fn new(year: u16, month: u8, day: u8) -> Date {
        Date { year, month, day }
    }
}

impl Prio {
    pub fn new(major: u32, minor: u32) -> Prio {
        Prio { major, minor }
    }
}

impl Paths {
    pub fn new() -> Paths {
        Default::default()
    }
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }
    pub fn insert(&mut self, path: &Path) {
        if !self.data.iter().any(|p| p == path) {
            self.data.push(path.clone());
        }
    }
    pub fn merge(&mut self, ctx: &Paths) -> util::Result<()> {
        for path in &ctx.data {
            self.insert(path);
        }
        Ok(())
    }
    pub fn has(&self, needle: &Path) -> bool {
        true
    }
    pub fn resolve(&self, rel: &Path) -> Option<Path> {
        if rel.is_absolute {
            Some(rel.clone())
        } else {
            for path in &self.data {
                let mut rel_parts = rel.parts.iter();
                let mut rel_part_opt = rel_parts.next();
                for part in &path.parts {
                    if let Some(rel_part) = rel_part_opt {
                        if part == rel_part {
                            rel_part_opt = rel_parts.next();
                        }
                    }
                }
                if rel_part_opt.is_none() {
                    return Some(path.clone());
                }
            }
            None
        }
    }
}

impl naft::ToNaft for Paths {
    fn to_naft(&self, p: &naft::Node) -> util::Result<()> {
        let n = p.node("Paths")?;
        for path in &self.data {
            path.to_naft(&n)?;
        }
        Ok(())
    }
}

impl std::fmt::Display for Paths {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut prefix = "";
        for path in &self.data {
            write!(f, "{prefix}{path}")?;
            prefix = " ";
        }
        Ok(())
    }
}

impl naft::ToNaft for Path {
    fn to_naft(&self, p: &naft::Node) -> util::Result<()> {
        let n = p.node("Path")?;
        n.attr("def", &self.is_definition);
        n.attr("abs", &self.is_absolute);
        for part in &self.parts {
            match part {
                Part::Text(part) => n.attr("part", part)?,
                _ => n.attr("?", &"?")?,
            }
        }
        Ok(())
    }
}

impl Path {
    pub fn new(is_definition: bool, is_absolute: bool, parts: Vec<&str>) -> Path {
        Path {
            is_definition,
            is_absolute,
            parts: parts.iter().map(|s| Part::Text(String::from(*s))).collect(),
        }
    }
    pub fn join(&self, rhs: &Path) -> Path {
        let mut res = self.clone();
        for v in &rhs.parts {
            res.parts.push(v.clone());
        }
        res
    }
}

impl std::fmt::Display for Path {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.is_definition {
            write!(f, "!")?;
        }
        if self.is_absolute {
            write!(f, ":")?;
        }

        let mut first = true;
        for part in &self.parts {
            if !first {
                write!(f, ":")?;
            }
            first = false;
            write!(f, "{part}")?;
        }

        Ok(())
    }
}

impl std::fmt::Display for Part {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Part::Text(v) => write!(f, "{v}"),
            Part::Date(v) => write!(f, "{v}"),
            Part::Duration(v) => write!(f, "{v}"),
            Part::Prio(v) => write!(f, "{v}"),
        }
    }
}

impl TryFrom<&str> for Date {
    type Error = util::ErrorType;
    fn try_from(s: &str) -> std::result::Result<Date, Self::Error> {
        let year;
        let month;
        let day;

        {
            let mut strange = strange::Strange::new(s);

            if let Some(s) = strange.read_decimals(4) {
                year = strange::Strange::new(s).read_number::<u16>().unwrap();
            } else {
                return Err(util::Error::create("Could not read year for Date"));
            }

            strange.read_char_if('-');

            if let Some(s) = strange.read_decimals(2) {
                month = strange::Strange::new(s).read_number::<u8>().unwrap();
            } else {
                return Err(util::Error::create("Could not read month for Date"));
            }

            strange.read_char_if('-');

            if let Some(s) = strange.read_decimals(2) {
                day = strange::Strange::new(s).read_number::<u8>().unwrap();
            } else {
                return Err(util::Error::create("Could not read day for Date"));
            }
        }

        Ok(Date { year, month, day })
    }
}

impl std::fmt::Display for Date {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:04}-{:02}-{:02}", self.year, self.month, self.day)?;
        Ok(())
    }
}

impl std::fmt::Display for Duration {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut m = self.minutes;
        let mut did_write = false;
        let mut cb = |div: u32, suffix: char| {
            let n = m / div;
            if n > 0 {
                write!(f, "{n}{suffix}").unwrap();
                did_write = true;
                m -= n * div;
            }
        };
        cb(60 * 8 * 5, 'w');
        cb(60 * 8, 'd');
        cb(60, 'h');
        cb(1, 'm');
        if !did_write {
            write!(f, "0m").unwrap();
        }
        Ok(())
    }
}

impl TryFrom<&str> for Prio {
    type Error = util::ErrorType;

    fn try_from(s: &str) -> std::result::Result<Prio, Self::Error> {
        let major: u32;
        let minor: u32;

        {
            let mut strange = strange::Strange::new(s);

            if let Some(ch) = strange.try_read_char_when(|ch| ch.is_ascii_alphabetic()) {
                if ch.is_uppercase() {
                    major = (ch as u32 - 'A' as u32) * 2;
                } else {
                    major = (ch as u32 - 'a' as u32) * 2 + 1;
                }
            } else {
                return Err(util::Error::create(
                    "Major for Prio should be [a-z] or [A-Z]",
                ));
            }

            if let Some(m) = strange.read_number() {
                minor = m;
            } else {
                return Err(util::Error::create("Minor for Prio should be a number"));
            }

            if !strange.is_empty() {
                return Err(util::Error::create("Prio cannot contain additional data"));
            }
        }

        Ok(Prio::new(major, minor))
    }
}

impl std::fmt::Display for Prio {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let ch: char;
        if self.major % 2 == 0 {
            ch = ('A' as u8 + (self.major / 2) as u8) as char;
        } else {
            ch = ('a' as u8 + (self.major / 2) as u8) as char;
        }
        write!(f, "{ch}").unwrap();
        write!(f, "{}", self.minor).unwrap();
        Ok(())
    }
}

impl TryFrom<&str> for Path {
    type Error = util::ErrorType;
    fn try_from(s: &str) -> util::Result<Path> {
        let mut strange = strange::Strange::new(s);

        let is_definition = strange.read_char_if('!');
        let is_absolute = strange.read_char_if(':');

        let mut parts = Vec::<Part>::new();
        while !strange.is_empty() {
            if let Some(str) = strange.read(|b| b.exclude().to_end().through(':')) {
                parts.push(Part::Text(str.into()));
            }
        }

        Ok(Path {
            is_definition,
            is_absolute,
            parts,
        })
    }
}

pub type Key = String;
pub type Value = value::Value;

#[derive(Debug, Eq, PartialEq, Clone)]
pub struct KeyValue(pub String, pub Option<String>);

#[derive(Default, Debug, Clone)]
pub struct KVSet {
    pub kvs: collections::BTreeMap<Key, Vec<String>>,
}

impl KVSet {
    pub fn new() -> KVSet {
        KVSet::default()
    }
    pub fn is_empty(&self) -> bool {
        self.kvs.is_empty()
    }
    pub fn has(&self, needle: &KeyValue) -> bool {
        let values = self.kvs.get(&needle.0);

        match &needle.1 {
            // None works like a wildcard
            None => values.is_some(),
            Some(nv) => {
                if let Some(values) = values {
                    values.iter().any(|value| value.to_string().ends_with(nv))
                } else {
                    false
                }
            }
        }
    }
    pub fn for_each(
        &self,
        mut cb: impl FnMut(&Key, Option<String>) -> util::Result<()>,
    ) -> util::Result<()> {
        for (key, values) in &self.kvs {
            if values.is_empty() {
                cb(key, None)?;
            } else {
                for value in values {
                    cb(key, Some(value.clone()))?;
                }
            }
        }
        Ok(())
    }
    pub fn insert(&mut self, kv: &KeyValue) {
        if !self.kvs.contains_key(&kv.0) {
            self.kvs.insert(kv.0.clone(), Vec::new());
        }
        if let Some(values) = self.kvs.get_mut(&kv.0) {
            if let Some(value) = &kv.1 {
                values.push(value.clone());
            }
        }
    }
    pub fn merge(&mut self, ctx: &KVSet) -> util::Result<()> {
        trace!("Merging");
        for (key_ctx, values_ctx) in &ctx.kvs {
            if !self.kvs.contains_key(key_ctx) {
                self.kvs.insert(key_ctx.clone(), Vec::new());
            }
            if let Some(values) = self.kvs.get_mut(key_ctx) {
                for value_ctx in values_ctx {
                    if !values.contains(value_ctx) {
                        values.push(value_ctx.clone());
                    }
                }
            }
        }
        Ok(())
    }
}

impl std::fmt::Display for KVSet {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // let mut prefix = "";
        // for (k, v) in &self.kvs {
        //     write!(f, "{prefix}{k}")?;
        //     prefix = " ";
        //     if v != &Value::None {
        //         write!(f, "={}", v)?;
        //     }
        // }
        Ok(())
    }
}

// &todo: move amp/value.rs UTs to here

// impl naft::ToNaft for KVSet {
//     fn to_naft(&self, p: &naft::Node) -> util::Result<()> {
//         // if !self.is_empty() {
//         //     let n = p.node("KVSet")?;
//         //     for (k, v) in &self.kvs {
//         //         n.attr(k, v)?;
//         //     }
//         // }
//         Ok(())
//     }
// }

// impl From<(String, Option<String>)> for KeyValue {
//     fn from(kv: (String, Option<String>)) -> KeyValue {
//         let mut key = kv.0;

//         let value = || -> util::Result<value::Value> {
//             let value = match kv.1.as_ref().map(|val| val.as_str()) {
//                 None => {
//                     if let Ok(status) = value::Status::try_from(key.as_str()) {
//                         key = "status".into();
//                         value::Value::Status(status)
//                     } else {
//                         value::Value::Tag(key.to_owned())
//                     }
//                 }
//                 Some(val) => match key.as_str() {
//                     "proj" => value::Value::Path(value::Path::try_from(val)?),
//                     "prio" => value::Value::Prio(value::Prio::try_from(val)?),
//                     "deadline" => value::Value::Date(value::Date::try_from(val)?),
//                     _ => return Err(util::Error::create("")),
//                 },
//             };

//             Ok(value)
//         }()
//         .unwrap_or_else(|_| match kv.1 {
//             None => value::Value::None,
//             Some(val) => value::Value::Tag(val),
//         });

//         KeyValue { key, value }
//     }
// }
