use crate::amp::value;
use std::{cmp, collections, path};

#[derive(Default)]
pub struct Answer {
    locations: Vec<Location>,
}

pub struct Location {
    pub filename: path::PathBuf,
    pub line_nr: u64,
    pub content: String,
    pub ctx: String,
    pub prio: value::Prio,
    pub proj: Option<value::Path>,
}

pub struct Meta {
    pub is_other_file: bool,
    pub is_first_for_file: bool,
}

pub enum By {
    Name,
    Prio,
}

impl Answer {
    pub fn new() -> Answer {
        Answer::default()
    }

    pub fn add(&mut self, location: Location) {
        self.locations.push(location);
    }

    pub fn order(&mut self, by: &By) {
        let cmp: fn(&Location, &Location) -> cmp::Ordering;
        match by {
            By::Name => cmp = Self::by_name,
            By::Prio => cmp = Self::by_prio,
        };
        self.locations.sort_by(|a, b| cmp(a, b));
    }

    pub fn each_location(&self, mut cb: impl FnMut(&Location, &Meta)) {
        let mut filename = path::PathBuf::new();
        let mut filenames = collections::BTreeSet::<path::PathBuf>::new();
        for location in &self.locations {
            let is_other_file = if location.filename != filename {
                filename = location.filename.clone();
                true
            } else {
                false
            };
            let is_first_for_file = !filenames.contains(&location.filename);
            if is_first_for_file {
                filenames.insert(location.filename.clone());
            }

            cb(
                location,
                &Meta {
                    is_other_file,
                    is_first_for_file,
                },
            );
        }
    }

    fn by_prio(a: &Location, b: &Location) -> cmp::Ordering {
        let a = (&a.prio, &ReversePath(&a.proj), &a.filename, a.line_nr);
        let b = (&b.prio, &ReversePath(&b.proj), &b.filename, b.line_nr);
        a.cmp(&b)
    }
    fn by_name(a: &Location, b: &Location) -> cmp::Ordering {
        let a = (&a.filename, a.line_nr);
        let b = (&b.filename, b.line_nr);
        a.cmp(&b)
    }
}

// We introduce a newtype to be able to reverse None/Some during Ord.cmp(). When both are Some(), nothing changes.
struct ReversePath<'a>(&'a Option<value::Path>);
impl<'a> Ord for ReversePath<'a> {
    fn cmp(&self, other: &Self) -> cmp::Ordering {
        match (&self.0, &other.0) {
            (None, None) => cmp::Ordering::Equal,
            (None, Some(_)) => cmp::Ordering::Greater,
            (Some(_), None) => cmp::Ordering::Less,
            (Some(a), Some(b)) => a.cmp(b),
        }
    }
}
impl<'a> PartialOrd for ReversePath<'a> {
    fn partial_cmp(&self, other: &Self) -> Option<cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl<'a> PartialEq for ReversePath<'a> {
    fn eq(&self, other: &Self) -> bool {
        self.0 == other.0
    }
}
impl<'a> Eq for ReversePath<'a> {}

#[cfg(test)]
mod tests {
    #[test]
    fn test_api() {}
}
