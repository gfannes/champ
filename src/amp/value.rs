use crate::rubr::strange;

#[derive(PartialEq, Eq, Debug)]
pub struct Path {
    absolute: bool,
    parts: Vec<String>,
}

#[derive(PartialEq, Eq, Debug)]
pub struct Date {
    year: u16,
    month: u8,
    day: u8,
}

#[derive(PartialEq, Eq, Debug)]
pub struct Duration {
    minutes: u32,
}

#[derive(PartialEq, Eq, Debug)]
pub struct Prio {
    major: Option<u32>,
    minor: u32,
}

pub enum State {
    Todo,
    Wip,
    Done,
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
    type Error = ();
    fn try_from(s: &str) -> std::result::Result<Path, Self::Error> {
        let mut absolute = false;
        let mut parts = Vec::new();

        {
            let mut strange = strange::Strange::new(s);
            if strange.is_empty() {
                return Err(());
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

impl Date {
    fn new(year: u16, month: u8, day: u8) -> Date {
        Date { year, month, day }
    }
    fn set_ctx(&mut self, rhs: &Self) {}
}
impl TryFrom<&str> for Date {
    type Error = ();
    fn try_from(s: &str) -> std::result::Result<Date, Self::Error> {
        let year;
        let month;
        let day;

        {
            let mut strange = strange::Strange::new(s);

            if let Some(s) = strange.read_decimals(4) {
                year = strange::Strange::new(s).read_number::<u16>().unwrap();
            } else {
                return Err(());
            }

            if let Some(s) = strange.read_decimals(2) {
                month = strange::Strange::new(s).read_number::<u8>().unwrap();
            } else {
                return Err(());
            }

            if let Some(s) = strange.read_decimals(2) {
                day = strange::Strange::new(s).read_number::<u8>().unwrap();
            } else {
                return Err(());
            }
        }

        Ok(Date { year, month, day })
    }
}

impl Duration {
    fn new(weeks: u32, days: u32, hours: u32, minutes: u32) -> Duration {
        let minutes = minutes + (hours + (days + weeks * 5) * 8) * 60;
        Duration { minutes }
    }
    fn set_ctx(&mut self, rhs: &Self) {}
}
impl TryFrom<&str> for Duration {
    type Error = ();
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
                        return Err(());
                    }
                } else {
                    return Err(());
                }
            }
        }

        Ok(Duration { minutes })
    }
}

impl Prio {
    fn new(major: Option<u32>, minor: u32) -> Prio {
        Prio { major, minor }
    }
}
impl TryFrom<&str> for Prio {
    type Error = ();
    fn try_from(s: &str) -> std::result::Result<Prio, Self::Error> {
        let major;
        let minor: u32;

        {
            let mut strange = strange::Strange::new(s);

            if let Some(ch) = strange.try_read_char_when(|ch| ch.is_ascii_alphabetic()) {
                major = Some(ch.to_ascii_lowercase() as u32 - 'a' as u32);
            } else {
                major = None;
            }

            if strange.is_empty() {
                minor = 0;
            } else if let Some(m) = strange.read_number() {
                minor = m;
            } else {
                return Err(());
            }
        }

        Ok(Prio::new(major, minor))
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
            ("1w2d3h4m", Some(Duration::new(1, 2, 3, 4))),
            ("2d3h1w4m", Some(Duration::new(1, 2, 3, 4))),
            ("1m2m3m", Some(Duration::new(0, 0, 0, 6))),
        ];

        for (s, exp) in scns {
            assert_eq!(Duration::try_from(s).ok(), exp);
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
            ("0", Some(Prio::new(None, 0))),
            ("1", Some(Prio::new(None, 1))),
            ("a1", Some(Prio::new(Some(0), 1))),
            ("A1", Some(Prio::new(Some(0), 1))),
            ("b1", Some(Prio::new(Some(1), 1))),
            ("b", Some(Prio::new(Some(1), 0))),
        ];

        for (s, exp) in scns {
            assert_eq!(Prio::try_from(s).ok(), exp);
        }
    }
}
