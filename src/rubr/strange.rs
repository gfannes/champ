// &todo: add peek functions
// &perf: convert to Vec<char> and work with that.
// - conversion can be done with is_ascii(), as_bytes() or chars().collect()

pub type Range = std::ops::Range<usize>;

use std::{fmt, ops};

#[derive(Clone)]
pub struct Strange<'a> {
    all: &'a str,
    safepoint: &'a str,
    rest: &'a str,
}

impl<'a> Strange<'a> {
    pub fn new(content: &str) -> Strange {
        Strange {
            all: content,
            safepoint: content,
            rest: content,
        }
    }

    pub fn to_str(&self) -> &str {
        self.rest
    }
    pub fn to_string(&self) -> String {
        self.to_str().to_owned()
    }

    pub fn is_empty(&self) -> bool {
        self.rest.is_empty()
    }
    pub fn len(&self) -> usize {
        self.rest.len()
    }

    pub fn index(&self) -> usize {
        distance(self.all, self.rest)
    }

    pub fn read_char(&mut self) -> bool {
        self.try_read_char().is_some()
    }
    pub fn try_read_char(&mut self) -> Option<char> {
        split_first(self.rest).and_then(|(ch, rest)| {
            self.rest = rest;
            Some(ch)
        })
    }

    pub fn read_char_if(&mut self, wanted: char) -> bool {
        self.try_read_char_if(wanted).is_some()
    }
    pub fn try_read_char_if(&mut self, wanted: char) -> Option<char> {
        split_first(self.rest).and_then(|(ch, rest)| {
            (ch == wanted).then(|| {
                self.rest = rest;
                ch
            })
        })
    }

    pub fn read_char_when(&mut self, cb: impl FnOnce(char) -> bool) -> bool {
        self.try_read_char_when(cb).is_some()
    }
    pub fn try_read_char_when(&mut self, cb: impl FnOnce(char) -> bool) -> Option<char> {
        split_first(self.rest).and_then(|(ch, rest)| {
            cb(ch).then(|| {
                self.rest = rest;
                ch
            })
        })
    }

    pub fn unwrite_char_if(&mut self, wanted: char) -> bool {
        self.try_unwrite_char_if(wanted).is_some()
    }

    pub fn try_unwrite_char_if(&mut self, wanted: char) -> Option<char> {
        split_last(self.rest).and_then(|(rest, ch)| {
            (ch == wanted).then(|| {
                self.rest = rest;
                ch
            })
        })
    }
    pub fn read_all(&mut self) -> Option<&str> {
        (!self.is_empty()).then(|| {
            let ret = self.rest;
            self.rest = &self.rest[self.rest.len()..];
            ret
        })
    }

    pub fn read_until_exc(&mut self, ch: char) -> Option<&str> {
        self.rest.find(ch).and_then(|ix| {
            let (first, rest) = self.rest.split_at(ix);
            self.rest = rest;
            Some(first)
        })
    }
    pub fn read_until_exc_or_end<'b>(&'b mut self, ch: char) -> Option<&'a str> {
        self.rest
            .find(ch)
            .and_then(|ix| {
                let (first, rest) = self.rest.split_at(ix);
                self.rest = rest;
                Some(first)
            })
            .or_else(|| {
                (!self.rest.is_empty()).then(|| {
                    let rest = self.rest;
                    self.rest = &self.rest[self.rest.len()..];
                    rest
                })
            })
    }

    pub fn read_until_inc(&mut self, ch: char) -> Option<&str> {
        self.rest.find(ch).and_then(|ix| {
            let (first, rest) = self.rest.split_at(ix + ch.len_utf8());
            self.rest = rest;
            Some(first)
        })
    }

    pub fn read_decimals(&mut self, count: usize) -> Option<&str> {
        if self.len() < count {
            return None;
        }

        let sp = self.rest;
        let mut cnt = count;
        for ch in self.rest.chars() {
            if cnt == 0 {
                break;
            }
            if '0' <= ch && ch <= '9' {
                cnt -= 1;
            } else {
                break;
            }
        }

        if cnt == 0 {
            self.rest = &self.rest[count..];
            Some(&sp[0..count])
        } else {
            self.rest = sp;
            None
        }
    }

    pub fn read_number<T: ops::Add + ops::Mul>(&mut self) -> Option<T>
    where
        T: ops::Add<Output = T> + ops::Mul<Output = T> + From<u8> + fmt::Debug,
    {
        let mut ret = None;
        while let Some(ch) = self.try_read_char_when(|ch| '0' <= ch && ch <= '9') {
            let dec = T::from(ch as u8 - '0' as u8);
            if let Some(mut v) = ret {
                v = v * T::from(10) + dec;
                ret = Some(v);
            } else {
                ret = Some(dec);
            }
        }
        ret
    }

    // Builder-style reading
    pub fn read<'b>(&'b mut self, cb: impl FnOnce(&mut Config) -> ()) -> Option<&'a str> {
        let mut config = Config::default();
        cb(&mut config);

        config.needle.and_then(|needle| {
            let split_ix: usize;
            let drop_needle: bool;
            if let Some(ix) = self.rest.find(needle) {
                if config.include {
                    split_ix = ix + needle.len_utf8();
                    drop_needle = false;
                } else {
                    split_ix = ix;
                    drop_needle = config.through;
                }
            } else if config.to_end && !self.rest.is_empty() {
                split_ix = self.rest.len();
                drop_needle = false;
            } else {
                return None;
            }

            let (first, rest) = self.rest.split_at(split_ix);
            if drop_needle {
                self.rest = &rest[needle.len_utf8()..];
            } else {
                self.rest = rest;
            }

            Some(first)
        })
    }

    pub fn reset(&mut self) {
        self.rest = self.safepoint;
    }

    pub fn save(&mut self) {
        self.safepoint = self.rest;
    }

    pub fn pop_str(&mut self) -> &str {
        let ret = &self.safepoint[..distance(self.safepoint, self.rest)];
        self.save();
        ret
    }
    pub fn pop_range(&mut self) -> Range {
        let ret = Range {
            start: distance(self.all, self.safepoint),
            end: distance(self.all, self.rest),
        };
        self.save();
        ret
    }
}

// Builder-style configuration for Strange.read()
#[derive(Default)]
pub struct Config {
    needle: Option<char>,
    through: bool,
    include: bool,
    to_end: bool,
}

impl Config {
    // Remove needle from Strange
    // Returns nothing by design: can be used to terminate a call chain, handy to avoid `{;}` in the callback
    pub fn through(&mut self, needle: char) {
        self.needle = Some(needle);
        self.through = true;
    }
    // Leave needle in Strange
    // Returns nothing by design: can be used to terminate a call chain, handy to avoid `{;}` in the callback
    pub fn until(&mut self, needle: char) {
        self.needle = Some(needle);
        self.through = false;
    }

    // Include needle into Strange.read()'s output
    pub fn include(&mut self) -> &mut Self {
        self.include = true;
        self
    }
    // Do not include needle into Strange.read()'s output
    pub fn exclude(&mut self) -> &mut Self {
        self.include = false;
        self
    }

    // If no match is found, read to the end of Strange
    pub fn to_end(&mut self) -> &mut Self {
        self.to_end = true;
        self
    }
}

fn split_first<'a>(content: &'a str) -> Option<(char, &'a str)> {
    content
        .chars()
        .next()
        .and_then(|ch| Some((ch, &content[ch.len_utf8()..])))
}

fn split_last<'a>(content: &'a str) -> Option<(&'a str, char)> {
    content
        .chars()
        .next_back()
        .and_then(|ch| Some((&content[..content.len() - ch.len_utf8()], ch)))
}

fn distance(from: &str, to: &str) -> usize {
    to.as_ptr() as usize - from.as_ptr() as usize
}

pub fn main() {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scn() {
        let s = Strange::new("abc");
        assert_eq!(s.to_str(), "abc");

        {
            let mut s = s.clone();
            if s.read_char_if('a') && s.read_char_if('b') {
                assert_eq!(s.pop_str(), "ab");
            }
            assert_eq!(s.to_str(), "c");
        }

        {
            let mut s = s.clone();
            if s.read_char_if('a') && s.read_char_if('b') {
                assert_eq!(s.pop_range(), 0..2);
            }
            assert_eq!(s.to_str(), "c");
        }

        {
            let mut s = s.clone();
            if s.read_char_if('a') && s.read_char_if('b') {
                s.reset();
            }
            assert_eq!(s.to_str(), "abc");
        }

        {
            let mut s = s.clone();
            s.try_read_char_if('a')
                .and_then(|_| s.try_read_char_if('b'));
            assert_eq!(s.to_str(), "c");
        }

        {
            let mut s = s.clone();
            s.read_char_when(|ch| match ch {
                'a' | 'b' => true,
                _ => false,
            });
            assert_eq!(s.to_str(), "bc");
        }
    }

    #[test]
    fn test_read_until() {
        let mut strange = Strange::new("abc def ghi");
        assert_eq!(strange.read_until_exc(' '), Some("abc"));
        assert!(strange.read_char_if(' '));
        assert_eq!(strange.read_until_inc(' '), Some("def "));
        assert_eq!(strange.to_str(), "ghi");
        assert_eq!(strange.read_until_exc_or_end(' '), Some("ghi"));
        assert_eq!(strange.read_until_exc_or_end(' '), None);
    }

    #[test]
    fn test_perf() {
        // let len = 1024 * 1024 * 1024;
        let len = 1024 * 1024;
        let content = "a".repeat(len);
        let mut s = Strange::new(&content);
        while s.read_char_if('a') {
            s.pop_str();
        }
        assert_eq!(s.to_str(), "");
    }

    #[test]
    fn test_read_decimals() {
        let mut s = Strange::new("1234");
        assert_eq!(s.read_decimals(0), Some(""));
        assert_eq!(s.read_decimals(1), Some("1"));
        assert_eq!(s.read_decimals(3), Some("234"));
        assert_eq!(s.read_decimals(1), None);
    }

    #[test]
    fn test_read_number() {
        let scns = [
            ("", None),
            ("abc", None),
            ("0", Some(0 as u32)),
            ("1234", Some(1234 as u32)),
        ];

        for (s, exp) in scns {
            println!("--------------- {s}");
            let mut s = Strange::new(s);
            assert_eq!(s.read_number::<u32>(), exp);
        }
    }
}
