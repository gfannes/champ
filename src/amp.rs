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

    pub fn matches_with(&self, needle: &Path) -> bool {
        self.data
            .iter()
            .any(|path| path.matches_with(needle, false))
    }

    pub fn resolve(&self, rel: &Path) -> Option<Path> {
        if rel.is_absolute {
            Some(rel.clone())
        } else {
            for path in &self.data {
                if let Some(p) = path.create_from_template(rel) {
                    return Some(p);
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

    // `as_template` indicates if `self` is a template. If so, for non-Text Parts, only type compatibility is checked
    pub fn matches_with(&self, rhs: &Self, as_template: bool) -> bool {
        // For an absolute Path, we expect a match immediately, hence we act as if we already found a match
        let mut found_match = rhs.is_absolute;

        let mut lhs = self.parts.iter();
        let mut rhs = rhs.parts.iter();

        while let Some(rhs) = rhs.next() {
            while let Some(lhs) = lhs.next() {
                let is_match = match (lhs, rhs) {
                    (Part::Text(lhs), Part::Text(rhs)) => lhs == rhs,
                    (Part::Date(lhs), Part::Date(rhs)) => as_template || lhs == rhs,
                    (Part::Duration(lhs), Part::Duration(rhs)) => as_template || lhs == rhs,
                    (Part::Prio(lhs), Part::Prio(rhs)) => as_template || lhs == rhs,

                    (Part::Date(lhs), Part::Text(rhs)) => {
                        if let Ok(rhs) = &Date::try_from(rhs.as_str()) {
                            as_template || lhs == rhs
                        } else {
                            false
                        }
                    }
                    (Part::Duration(lhs), Part::Text(rhs)) => {
                        if let Ok(rhs) = &Duration::try_from(rhs.as_str()) {
                            as_template || lhs == rhs
                        } else {
                            false
                        }
                    }
                    (Part::Prio(lhs), Part::Text(rhs)) => {
                        if let Ok(rhs) = &Prio::try_from(rhs.as_str()) {
                            as_template || lhs == rhs
                        } else {
                            false
                        }
                    }

                    _ => false,
                };

                if is_match {
                    // Once we found a match, we expect we keep matching
                    found_match = true;
                    break;
                } else {
                    if found_match {
                        // Found a mismatch
                        return false;
                    }
                }
            }

            if !found_match {
                return false;
            }
        }

        // Could match all parts from rhs: we found a match
        true
    }

    fn create_from_template(&self, rhs: &Self) -> Option<Path> {
        let mut ret = Path::new(rhs.is_definition, true, Vec::new());

        // For an absolute Path, we expect a match immediately, hence we act as if we already found a match
        let mut found_match_before = rhs.is_absolute;

        let mut lhs = self.parts.iter();
        let mut rhs = rhs.parts.iter();
        let mut cur_rhs_opt = rhs.next();

        while let Some(lhs) = lhs.next() {
            if let Some(cur_rhs) = cur_rhs_opt {
                let part = match (lhs, cur_rhs) {
                    (Part::Text(lhs), Part::Text(rhs)) => {
                        (lhs == rhs).then_some(Part::Text(rhs.to_owned()))
                    }
                    (Part::Date(_), Part::Date(rhs)) => Some(Part::Date(rhs.to_owned())),
                    (Part::Duration(_), Part::Duration(rhs)) => {
                        Some(Part::Duration(rhs.to_owned()))
                    }
                    (Part::Prio(_), Part::Prio(rhs)) => Some(Part::Prio(rhs.to_owned())),

                    (Part::Date(_), Part::Text(rhs)) => {
                        if let Ok(rhs) = Date::try_from(rhs.as_str()) {
                            Some(Part::Date(rhs))
                        } else {
                            None
                        }
                    }
                    (Part::Duration(_), Part::Text(rhs)) => {
                        if let Ok(rhs) = Duration::try_from(rhs.as_str()) {
                            Some(Part::Duration(rhs))
                        } else {
                            None
                        }
                    }
                    (Part::Prio(_), Part::Text(rhs)) => {
                        if let Ok(rhs) = Prio::try_from(rhs.as_str()) {
                            Some(Part::Prio(rhs))
                        } else {
                            None
                        }
                    }

                    _ => None,
                };

                if let Some(part) = part {
                    // Once we found a match, we expect we keep matching
                    found_match_before = true;
                    ret.parts.push(part);
                    cur_rhs_opt = rhs.next();
                } else {
                    if found_match_before {
                        // Found a mismatch
                        return None;
                    } else {
                        ret.parts.push(lhs.clone());
                    }
                }
            } else {
                // rhs should match until the end
                return None;
            }
        }

        if cur_rhs_opt.is_some() {
            // Could not match all parts from rhs
            return None;
        }

        // Could match all parts from rhs: we found a match
        Some(ret)
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

impl TryFrom<&str> for Duration {
    type Error = util::ErrorType;
    fn try_from(s: &str) -> std::result::Result<Duration, Self::Error> {
        let mut minutes = 0 as u32;

        {
            let mut strange = strange::Strange::new(s);
            while !strange.is_empty() {
                if let Some(v) = strange.read_number::<u32>() {
                    if !strange.read_char_when(|ch| {
                        match ch {
                            'w' => minutes += v * 60 * 8 * 5,
                            'd' => minutes += v * 60 * 8,
                            'h' => minutes += v * 60,
                            'm' => minutes += v,
                            _ => return false,
                        }
                        true
                    }) {
                        return Err(util::Error::create(format!(
                            "Unexpected unit found in Duration '{}'",
                            s
                        )));
                    }
                } else {
                    return Err(util::Error::create(format!(
                        "Could not read number from Duration '{}'",
                        s
                    )));
                }
            }
        }

        Ok(Duration { minutes })
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
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_paths_matches_with() -> util::Result<()> {
        let scns = [
            (vec![":a", ":b"], "a", true),
            (vec![":a", ":b"], "b", true),
            (vec![":a", ":b"], "c", false),
        ];
        for (paths_str, needle, exp) in scns {
            let mut paths = Paths::new();
            for path_str in paths_str {
                paths.insert(&Path::try_from(path_str)?);
            }

            let needle = Path::try_from(needle)?;
            assert_eq!(paths.matches_with(&needle), exp);
        }
        Ok(())
    }

    #[test]
    fn test_path_matches_with_text() -> util::Result<()> {
        let scns = [
            ("a", "a", true),
            (":a", "a", true),
            (":a", ":a", true),
            ("a:b", "a", true),
            (":a:b", "a", true),
            (":a:b", ":a:b", true),
            ("a:b", "b", true),
            (":a:b", "b", true),
            (":a:b", ":b", false),
            ("ab", "a", false),
            ("ab", "b", false),
            (":a:b", "c", false),
        ];
        for (path, needle, exp) in scns {
            let path = Path::try_from(path)?;
            let needle = Path::try_from(needle)?;
            assert_eq!(path.matches_with(&needle, true), exp);
        }
        Ok(())
    }

    #[test]
    fn test_path_matches_with_prio() -> util::Result<()> {
        let mut path = Path::new(true, true, vec!["prio"]);
        path.parts.push(Part::Prio(Prio::new(0, 0)));

        let scns = [
            ("prio", true, true),
            ("prio:A0", true, true),
            ("prio:a0", true, true),
            ("prio:b1", true, true),
            ("prio:b1", false, false),
            ("prio:aa0", true, false),
        ];
        for (needle, as_template, exp) in scns {
            println!("----------------- {needle} {exp}");
            let needle = Path::try_from(needle)?;
            assert_eq!(path.matches_with(&needle, as_template), exp);
        }
        Ok(())
    }

    #[test]
    fn test_path_create_from_template() -> util::Result<()> {
        let mut abc = Path::new(true, true, vec!["abc"]);

        let mut prio = Path::new(true, true, vec!["prio"]);
        prio.parts.push(Part::Prio(Prio::new(0, 0)));

        let scns = [
            (&abc, "abc", Some("abc"), None),
            (&abc, "abd", None, None),
            (&prio, "prio", None, None),
            (&prio, "prio:aa0", None, None),
            (&prio, "prio:A0", Some("prio"), Some("A0")),
            (&prio, "prio:a0", Some("prio"), Some("a0")),
            (&prio, "prio:b1", Some("prio"), Some("b1")),
        ];
        for (template, path, base, prio) in scns {
            println!("----------------- {path} {:?} {:?}", base, prio);
            let path = Path::try_from(path)?;
            let new_path = template.create_from_template(&path);
            let exp = base.map(|base| {
                let mut p = Path::new(false, true, vec![base]);
                if let Some(prio) = prio {
                    p.parts.push(Part::Prio(Prio::try_from(prio).unwrap()));
                }
                p
            });
            assert_eq!(new_path, exp);
        }
        Ok(())
    }
}
