use crate::{rubr::strange, util};
use std::fmt::Write;

#[derive(PartialEq, Eq, Debug, Clone, PartialOrd, Ord)]
pub enum Value {
    None,
    Tag(String),
    Path(Path),
    Date(Date),
    Duration(Duration),
    Prio(Prio),
}

#[derive(PartialEq, Eq, Debug, Clone, Default, PartialOrd, Ord)]
pub struct Path {
    absolute: bool,
    parts: Vec<String>,
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
    major: Option<u32>,
    minor: u32,
}

pub enum State {
    Todo,
    Wip,
    Done,
}

impl Value {
    pub fn is_none(&self) -> bool {
        self == &Value::None
    }
}
impl ToString for Value {
    fn to_string(&self) -> String {
        match self {
            Value::None => "".into(),
            Value::Tag(s) => s.clone(),
            Value::Path(p) => p.to_string(),
            Value::Date(d) => d.to_string(),
            Value::Duration(d) => d.to_string(),
            Value::Prio(p) => p.to_string(),
        }
    }
}
impl Default for Value {
    fn default() -> Value {
        Value::None
    }
}

impl Path {
    fn new(absolute: bool, parts: &[&str]) -> Path {
        let parts = parts.iter().map(ToString::to_string).collect();
        Path { absolute, parts }
    }
    fn set_ctx(&mut self, ctx: &Self) {
        if !self.absolute {
            let mut my_parts = std::mem::replace(&mut self.parts, ctx.parts.clone());
            self.parts.append(&mut my_parts);

            self.absolute = ctx.absolute;
        }
    }
}
impl TryFrom<&str> for Path {
    type Error = util::ErrorType;
    fn try_from(s: &str) -> std::result::Result<Path, Self::Error> {
        let mut absolute = false;
        let mut parts = Vec::new();

        {
            let mut strange = strange::Strange::new(s);
            if strange.is_empty() {
                return Err(util::Error::create("Cannot create Path from empty &str"));
            }
            if strange.read_char_if('/') {
                absolute = true;
            }
            while !strange.is_empty() {
                if let Some(s) = strange.read(|b| b.exclude().to_end().through('/')) {
                    parts.push(s);
                }
            }
        }

        Ok(Path::new(absolute, &parts))
    }
}
impl ToString for Path {
    fn to_string(&self) -> String {
        let mut ret = String::new();

        let mut do_add_delim = self.absolute;
        let mut add_delim = |s: &mut String, arm: bool| {
            if do_add_delim {
                s.push_str("/");
            }
            do_add_delim = arm;
        };

        add_delim(&mut ret, false);
        for part in self.parts.iter() {
            add_delim(&mut ret, true);
            ret.push_str(part);
        }

        ret
    }
}

impl Date {
    fn new(year: u16, month: u8, day: u8) -> Date {
        Date { year, month, day }
    }
    fn set_ctx(&mut self, _rhs: &Self) {}
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

            if let Some(s) = strange.read_decimals(2) {
                month = strange::Strange::new(s).read_number::<u8>().unwrap();
            } else {
                return Err(util::Error::create("Could not read month for Date"));
            }

            if let Some(s) = strange.read_decimals(2) {
                day = strange::Strange::new(s).read_number::<u8>().unwrap();
            } else {
                return Err(util::Error::create("Could not read day for Date"));
            }
        }

        Ok(Date { year, month, day })
    }
}
impl ToString for Date {
    fn to_string(&self) -> String {
        format!("{:.4}{:02.2}{:02.2}", self.year, self.month, self.day)
    }
}

impl Duration {
    fn new(weeks: u32, days: u32, hours: u32, minutes: u32) -> Duration {
        let minutes = minutes + (hours + (days + weeks * 5) * 8) * 60;
        Duration { minutes }
    }
    fn set_ctx(&mut self, _rhs: &Self) {}
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
impl ToString for Duration {
    fn to_string(&self) -> String {
        let mut ret = String::new();
        let mut m = self.minutes;
        let mut cb = |div: u32, suffix: char| {
            let n = m / div;
            if n > 0 {
                write!(&mut ret, "{n}{suffix}").unwrap();
                m -= n * div;
            }
        };
        cb(60 * 8 * 5, 'w');
        cb(60 * 8, 'd');
        cb(60, 'h');
        cb(1, 'm');
        ret
    }
}

impl Prio {
    fn new(major: Option<u32>, minor: u32) -> Prio {
        Prio { major, minor }
    }
}
impl TryFrom<&str> for Prio {
    type Error = util::ErrorType;
    fn try_from(s: &str) -> std::result::Result<Prio, Self::Error> {
        let major;
        let minor: u32;

        {
            let mut strange = strange::Strange::new(s);

            if let Some(ch) = strange.try_read_char_when(|ch| ch.is_ascii_alphabetic()) {
                if ch.is_uppercase() {
                    major = Some((ch as u32 - 'A' as u32) * 2);
                } else {
                    major = Some((ch as u32 - 'a' as u32) * 2 + 1);
                }
            } else {
                major = None;
            }

            if strange.is_empty() {
                minor = 0;
            } else if let Some(m) = strange.read_number() {
                minor = m;
            } else {
                return Err(util::Error::create(
                    "Minor for Prio should either be absent or a number",
                ));
            }
        }

        Ok(Prio::new(major, minor))
    }
}
impl ToString for Prio {
    fn to_string(&self) -> String {
        let mut ret = String::new();
        if let Some(major) = self.major {
            let ch: char;
            if major % 2 == 0 {
                ch = ('A' as u8 + (major / 2) as u8) as char;
            } else {
                ch = ('a' as u8 + (major / 2) as u8) as char;
            }
            write!(&mut ret, "{ch}").unwrap();
        }
        write!(&mut ret, "{}", self.minor).unwrap();
        ret
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_path_try_from() {
        let scns = [
            ("", None as Option<Path>),
            ("a", Some(Path::new(false, &["a"]))),
            ("a/b", Some(Path::new(false, &["a", "b"]))),
            ("/", Some(Path::new(true, &[]))),
            ("/a/b", Some(Path::new(true, &["a", "b"]))),
        ];

        for (s, exp) in scns {
            assert_eq!(Path::try_from(s).ok(), exp);
            if let Some(exp) = &exp {
                assert_eq!(exp.to_string(), s);
            }
        }
    }

    #[test]
    fn test_path_set_ctx() {
        let scns = [
            (
                Path::new(false, &["a"]),
                Path::new(false, &["ctx"]),
                Path::new(false, &["ctx", "a"]),
            ),
            (
                Path::new(false, &["a"]),
                Path::new(true, &["ctx"]),
                Path::new(true, &["ctx", "a"]),
            ),
            (
                Path::new(true, &["a"]),
                Path::new(false, &["ctx"]),
                Path::new(true, &["a"]),
            ),
        ];

        for (mut a, ctx, exp) in scns {
            a.set_ctx(&ctx);
            assert_eq!(a, exp);
        }
    }

    #[test]
    fn test_date_try_from() {
        let scns = [("20241002", Some(Date::new(2024, 10, 2)))];

        for (s, exp) in scns {
            assert_eq!(Date::try_from(s).ok(), exp);
            assert_eq!(exp.unwrap().to_string(), s);
        }
    }

    #[test]
    fn test_date_set_ctx() {
        let scns = [
            (
                Date::new(2024, 10, 2),
                Date::new(2024, 10, 1),
                Date::new(2024, 10, 2),
            ),
            (
                Date::new(2024, 10, 2),
                Date::new(2024, 10, 2),
                Date::new(2024, 10, 2),
            ),
            (
                Date::new(2024, 10, 2),
                Date::new(2024, 10, 3),
                Date::new(2024, 10, 2),
            ),
        ];

        for (mut a, ctx, exp) in scns {
            a.set_ctx(&ctx);
            assert_eq!(a, exp);
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
    fn test_duration_set_ctx() {
        let scns = [
            (
                Duration::new(0, 0, 0, 2),
                Duration::new(0, 0, 0, 1),
                Duration::new(0, 0, 0, 2),
            ),
            (
                Duration::new(0, 0, 0, 2),
                Duration::new(0, 0, 0, 2),
                Duration::new(0, 0, 0, 2),
            ),
            (
                Duration::new(0, 0, 0, 2),
                Duration::new(0, 0, 0, 3),
                Duration::new(0, 0, 0, 2),
            ),
        ];

        for (mut a, ctx, exp) in scns {
            a.set_ctx(&ctx);
            assert_eq!(a, exp);
        }
    }

    #[test]
    fn test_prio_try_from() {
        let scns = [
            ("0", Some(Prio::new(None, 0)), true),
            ("1", Some(Prio::new(None, 1)), true),
            ("a1", Some(Prio::new(Some(1), 1)), true),
            ("A1", Some(Prio::new(Some(0), 1)), true),
            ("b1", Some(Prio::new(Some(3), 1)), true),
            ("b", Some(Prio::new(Some(3), 0)), false),
        ];

        for (s, exp, do_check_to_string) in scns {
            assert_eq!(Prio::try_from(s).ok(), exp);
            if do_check_to_string {
                assert_eq!(exp.unwrap().to_string(), s);
            }
        }
    }
}
