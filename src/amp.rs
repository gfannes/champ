pub mod parse;

use crate::{
    rubr::{naft, strange},
    util,
};

use tracing::info;

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
    Tag(Tag),
    Status(Status),
    Date(Date),
    Duration(Duration),
    Prio(Prio),
}

#[derive(PartialEq, Eq, Debug, Clone, Default, PartialOrd, Ord)]
pub struct Tag {
    pub text: String,
    pub exclusive: bool,
}

#[derive(PartialEq, Eq, Debug, Clone, PartialOrd, Ord)]
pub enum Status {
    Todo,
    Wip,
    Done,
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

impl Status {
    pub fn new() -> Status {
        Default::default()
    }
}

impl Default for Status {
    fn default() -> Self {
        Status::Todo
    }
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

    pub fn insert(&mut self, path: Path) {
        if !self.data.iter().any(|p| p == &path) {
            self.data.push(path);
        }
    }

    pub fn has_variant(&self, rhs: &Path) -> bool {
        self.data.iter().any(|lhs| lhs.is_variant(rhs))
    }

    pub fn merge(&mut self, ctx: &Paths) -> util::Result<()> {
        for path in &ctx.data {
            self.insert(path.clone());
        }
        Ok(())
    }

    pub fn matches_with(&self, needle: &Path) -> bool {
        self.data
            .iter()
            .any(|path| path.matches_with(needle, false))
    }

    pub fn resolve(&self, rel: &Path) -> Option<Path> {
        self.data
            .iter()
            .find_map(|path| path.create_from_template(rel))
    }
}

impl naft::ToNaft for Paths {
    fn to_naft(&self, b: &mut naft::Body<'_, '_>) -> std::fmt::Result {
        b.node(&"Paths")?;
        let mut b = b.nest();
        for path in &self.data {
            path.to_naft(&mut b)?;
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
    fn to_naft(&self, b: &mut naft::Body<'_, '_>) -> std::fmt::Result {
        b.node(&"Path")?;
        b.attr("def", &self.is_definition)?;
        b.attr("abs", &self.is_absolute)?;
        for part in &self.parts {
            match part {
                Part::Tag(tag) => {
                    b.attr("text", &tag.text)?;
                    b.attr("exclusive", &tag.exclusive)?;
                }
                _ => b.attr("?", &"?")?,
            }
        }
        Ok(())
    }
}

impl Path {
    pub fn new(is_definition: bool, is_absolute: bool, parts: &[&str]) -> Path {
        Path {
            is_definition,
            is_absolute,
            parts: parts.iter().map(|s| Part::Tag(Tag::from(*s))).collect(),
        }
    }

    pub fn join(&self, rhs: &Path) -> Path {
        let mut res = self.clone();
        for v in &rhs.parts {
            res.parts.push(v.clone());
        }
        res
    }

    // A variant of rhs is a Path that builds on rhs or where the first non-common parts are both exclusive
    pub fn is_variant(&self, rhs: &Path) -> bool {
        let mut common = std::ops::Range::<usize>::default();
        for (ix, lhs_part) in self.parts.iter().enumerate() {
            if let Some(rhs_part) = rhs.parts.get(ix) {
                if lhs_part == rhs_part {
                    common.end = ix + 1;
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        let is_exclusive = |part: &Part| match part {
            Part::Tag(tag) => tag.exclusive,
            _ => false,
        };

        if common.len() == rhs.parts.len() {
            // self builds on rhs and is more specific
            true
        } else if common.len() == self.parts.len() {
            // rhs builds on self, and is not equal but more specific
            false
        } else if is_exclusive(&self.parts[common.end]) && is_exclusive(&rhs.parts[common.end]) {
            true
        } else {
            false
        }
    }

    pub fn get_prio(&self) -> Option<&Prio> {
        for part in &self.parts {
            match part {
                Part::Prio(p) => return Some(p),
                _ => {}
            }
        }
        None
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
                    (Part::Tag(lhs), Part::Tag(rhs)) => &lhs.text == &rhs.text,
                    (Part::Status(lhs), Part::Status(rhs)) => as_template || lhs == rhs,
                    (Part::Date(lhs), Part::Date(rhs)) => as_template || lhs == rhs,
                    (Part::Duration(lhs), Part::Duration(rhs)) => as_template || lhs == rhs,
                    (Part::Prio(lhs), Part::Prio(rhs)) => as_template || lhs == rhs,

                    (Part::Status(lhs), Part::Tag(rhs)) => {
                        if let Ok(rhs) = &Status::try_from(rhs.text.as_str()) {
                            as_template || lhs == rhs
                        } else {
                            false
                        }
                    }
                    (Part::Date(lhs), Part::Tag(rhs)) => {
                        if let Ok(rhs) = &Date::try_from(rhs.text.as_str()) {
                            as_template || lhs == rhs
                        } else {
                            false
                        }
                    }
                    (Part::Duration(lhs), Part::Tag(rhs)) => {
                        if let Ok(rhs) = &Duration::try_from(rhs.text.as_str()) {
                            as_template || lhs == rhs
                        } else {
                            false
                        }
                    }
                    (Part::Prio(lhs), Part::Tag(rhs)) => {
                        if let Ok(rhs) = &Prio::try_from(rhs.text.as_str()) {
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
        let mut ret = Path::new(rhs.is_definition, true, &[]);

        // For an absolute Path, we expect a match immediately, hence we act as if we already found a match
        let mut found_match_before = rhs.is_absolute;

        let mut lhs = self.parts.iter();
        let mut rhs = rhs.parts.iter();
        let mut cur_rhs_opt = rhs.next();

        while let Some(lhs) = lhs.next() {
            if let Some(cur_rhs) = cur_rhs_opt {
                let part = match (lhs, cur_rhs) {
                    (Part::Tag(lhs), Part::Tag(rhs)) => {
                        (&lhs.text == &rhs.text).then_some(Part::Tag(lhs.to_owned()))
                    }
                    (Part::Status(_), Part::Status(rhs)) => Some(Part::Status(rhs.to_owned())),
                    (Part::Date(_), Part::Date(rhs)) => Some(Part::Date(rhs.to_owned())),
                    (Part::Duration(_), Part::Duration(rhs)) => {
                        Some(Part::Duration(rhs.to_owned()))
                    }
                    (Part::Prio(_), Part::Prio(rhs)) => Some(Part::Prio(rhs.to_owned())),

                    (Part::Status(_), Part::Tag(rhs)) => {
                        if let Ok(rhs) = Status::try_from(rhs.text.as_str()) {
                            Some(Part::Status(rhs))
                        } else {
                            None
                        }
                    }
                    (Part::Date(_), Part::Tag(rhs)) => {
                        if let Ok(rhs) = Date::try_from(rhs.text.as_str()) {
                            Some(Part::Date(rhs))
                        } else {
                            None
                        }
                    }
                    (Part::Duration(_), Part::Tag(rhs)) => {
                        if let Ok(rhs) = Duration::try_from(rhs.text.as_str()) {
                            Some(Part::Duration(rhs))
                        } else {
                            None
                        }
                    }
                    (Part::Prio(_), Part::Tag(rhs)) => {
                        if let Ok(rhs) = Prio::try_from(rhs.text.as_str()) {
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

impl std::fmt::Display for Tag {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", &self.text)?;
        if self.exclusive {
            write!(f, "!")?;
        }
        Ok(())
    }
}

impl std::fmt::Display for Part {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Part::Tag(v) => write!(f, "{v}"),
            Part::Status(v) => write!(f, "{v}"),
            Part::Date(v) => write!(f, "{v}"),
            Part::Duration(v) => write!(f, "{v}"),
            Part::Prio(v) => write!(f, "{v}"),
        }
    }
}

impl From<&str> for Tag {
    fn from(value: &str) -> Self {
        let mut text = value;
        let exclusive;
        if text.ends_with("!") {
            text = &text[0..text.len() - 1];
            exclusive = true;
        } else {
            exclusive = false;
        }
        Tag {
            text: text.into(),
            exclusive,
        }
    }
}

impl TryFrom<&str> for Status {
    type Error = util::ErrorType;

    fn try_from(s: &str) -> std::result::Result<Status, Self::Error> {
        match s {
            "todo" => Ok(Status::Todo),
            "wip" => Ok(Status::Wip),
            "done" => Ok(Status::Done),
            _ => Err(util::Error::create("This is not a valid status")),
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

impl std::fmt::Display for Status {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Status::Todo => write!(f, "Todo"),
            Status::Wip => write!(f, "Wip"),
            Status::Done => write!(f, "Done"),
        }
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
                parts.push(Part::Tag(Tag::from(str)));
            }
        }

        Ok(Path {
            is_definition,
            is_absolute,
            parts,
        })
    }
}

#[derive(Debug, Eq, PartialEq, Clone)]
pub struct KeyValue(pub String, pub Option<String>);

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
                paths.insert(Path::try_from(path_str)?);
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
        let mut path = Path::new(true, true, &["prio"]);
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
        let abc = Path::new(true, true, &["abc"]);

        let mut prio = Path::new(true, true, &["prio"]);
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
                let mut p = Path::new(false, true, &[base]);
                if let Some(prio) = prio {
                    p.parts.push(Part::Prio(Prio::try_from(prio).unwrap()));
                }
                p
            });
            assert_eq!(new_path, exp);
        }
        Ok(())
    }

    #[test]
    fn test_path_try_from() {
        let scns = [
            ("", Some(Path::new(false, false, &[]))),
            ("a", Some(Path::new(false, false, &["a"]))),
            ("a:b", Some(Path::new(false, false, &["a", "b"]))),
            (":", Some(Path::new(false, true, &[]))),
            (":a:b", Some(Path::new(false, true, &["a", "b"]))),
        ];

        for (s, exp) in scns {
            assert_eq!(Path::try_from(s).ok(), exp);
            if let Some(exp) = &exp {
                assert_eq!(exp.to_string(), s);
            }
        }
    }

    #[test]
    fn test_tag_try_from() {
        let scns = [
            (
                "abc",
                Tag {
                    text: "abc".into(),
                    exclusive: false,
                },
            ),
            (
                "abc!",
                Tag {
                    text: "abc".into(),
                    exclusive: true,
                },
            ),
        ];

        for (s, exp) in scns {
            assert_eq!(Tag::from(s), exp);
            assert_eq!(exp.to_string(), s);
        }
    }

    #[test]
    fn test_status_try_from() {
        let scns = [("todo", Some(Status::Todo))];

        for (s, exp) in scns {
            assert_eq!(Status::try_from(s).ok(), exp);
            assert_eq!(exp.unwrap().to_string(), s);
        }
    }

    #[test]
    fn test_date_try_from() {
        let scns = [("2024-10-02", Some(Date::new(2024, 10, 2)))];

        for (s, exp) in scns {
            assert_eq!(Date::try_from(s).ok(), exp);
            assert_eq!(exp.unwrap().to_string(), s);
        }
    }

    #[test]
    fn test_duration_try_from() {
        let scns = [
            ("1w2d3h4m", Some(Duration::new(1, 2, 3, 4)), true),
            ("2d3h1w4m", Some(Duration::new(1, 2, 3, 4)), false),
            ("1m2m3m", Some(Duration::new(0, 0, 0, 6)), false),
        ];

        for (s, exp, check_to_string) in scns {
            assert_eq!(Duration::try_from(s).ok(), exp);
            if check_to_string {
                assert_eq!(exp.unwrap().to_string(), s);
            }
        }
    }

    #[test]
    fn test_prio_try_from() {
        let scns = [
            ("A0", Some(Prio::new(0, 0))),
            ("A1", Some(Prio::new(0, 1))),
            ("a1", Some(Prio::new(1, 1))),
            ("a1", Some(Prio::new(1, 1))),
            ("b0", Some(Prio::new(3, 0))),
            ("b1", Some(Prio::new(3, 1))),
        ];

        for (s, exp) in scns {
            assert_eq!(Prio::try_from(s).ok(), exp);
        }
    }

    #[test]
    fn test_paths_has_variant() -> util::Result<()> {
        let mut paths = Paths::new();

        paths.insert(Path::try_from(":a")?);
        paths.insert(Path::try_from(":e!")?);
        paths.insert(Path::try_from(":b:c:d")?);

        // Same
        assert_eq!(paths.has_variant(&Path::try_from(":a")?), true);
        assert_eq!(paths.has_variant(&Path::try_from(":b:c:d")?), true);
        assert_eq!(paths.has_variant(&Path::try_from(":e!")?), true);

        // Less specific
        assert_eq!(paths.has_variant(&Path::try_from(":b:c")?), true);
        assert_eq!(paths.has_variant(&Path::try_from(":b")?), true);

        // Exclusive
        assert_eq!(paths.has_variant(&Path::try_from(":f!")?), true);

        // Different
        assert_eq!(paths.has_variant(&Path::try_from(":a:b")?), false);
        assert_eq!(paths.has_variant(&Path::try_from(":d")?), false);
        assert_eq!(paths.has_variant(&Path::try_from(":b:c:e")?), false);
        assert_eq!(paths.has_variant(&Path::try_from(":b:d")?), false);
        assert_eq!(paths.has_variant(&Path::try_from(":d:e")?), false);

        Ok(())
    }

    #[test]
    fn test_paths_resolve() -> util::Result<()> {
        let mut paths = Paths::new();

        paths.insert(Path::try_from("!:todo!")?);
        // paths.insert(Path::try_from("!:done!")?);
        // paths.insert(Path::try_from("!:blocked")?);

        assert_eq!(
            paths.resolve(&Path::try_from("todo!")?),
            Path::try_from(":todo!").ok()
        );
        assert_eq!(
            paths.resolve(&Path::try_from("todo")?),
            Path::try_from(":todo!").ok()
        );

        Ok(())
    }
}
