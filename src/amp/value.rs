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

pub struct Prio {
    major: u8,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_path() {
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
    fn test_date() {
        let scns = [("20241002", Some(Date::new(2024, 10, 2)))];

        for (s, exp) in scns {
            assert_eq!(Date::try_from(s).ok(), exp);
        }
    }

    #[test]
    fn test_duration() {
        let scns = [
            ("1w2d3h4m", Some(Duration::new(1, 2, 3, 4))),
            ("2d3h1w4m", Some(Duration::new(1, 2, 3, 4))),
            ("1m2m3m", Some(Duration::new(0, 0, 0, 6))),
        ];

        for (s, exp) in scns {
            assert_eq!(Duration::try_from(s).ok(), exp);
        }
    }
}
