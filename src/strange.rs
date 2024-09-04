pub struct Strange<'a> {
    content: &'a str,
}

impl<'a> Strange<'a> {
    pub fn new(content: &'a str) -> Strange<'a> {
        Strange { content }
    }

    pub fn is_empty(&self) -> bool {
        self.content.is_empty()
    }
    pub fn str(&self) -> &str {
        self.content
    }
    pub fn len(&self) -> usize {
        self.content.len()
    }

    pub fn pop_char_if(&mut self, ch: char) -> Option<&str> {
        split_first(self.content).and_then(|(c, first, rest)| {
            (ch == c).then(|| {
                self.content = rest;
                first
            })
        })
    }

    pub fn pop_any_of(&mut self, chars: &[char]) -> Option<&str> {
        split_first(self.content).and_then(|(c, first, rest)| {
            chars.contains(&c).then(|| {
                self.content = rest;
                first
            })
        })
    }

    pub fn pop_until_exc(&mut self, ch: char) -> Option<&str> {
        self.content.find(ch).and_then(|ix| {
            let (first, rest) = self.content.split_at(ix);
            self.content = rest;
            Some(first)
        })
    }

    pub fn pop_until_inc(&mut self, ch: char) -> Option<&str> {
        self.content.find(ch).and_then(|ix| {
            let (first, rest) = self.content.split_at(ix + ch.len_utf8());
            self.content = rest;
            Some(first)
        })
    }
}

// Helper function to split a &str into (ch: char, first: &str, rest: &str), where ch and first contains the first UTF8 character, if any.
fn split_first<'a>(content: &'a str) -> Option<(char, &'a str, &'a str)> {
    content.chars().next().and_then(|ch| {
        let ch_len = ch.len_utf8();
        Some((ch, &content[..ch_len], &content[ch_len..]))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        let strange = Strange::new("abc");
        assert!(!strange.is_empty());
        assert!(strange.str() == "abc");
        assert!(strange.len() == 3);
    }

    #[test]
    fn test_pop_char_if() {
        let mut strange = Strange::new("abc");
        assert!(strange.pop_char_if('a') == Some("a"));
        assert!(strange.pop_char_if('a') == None);
        assert!(strange.pop_char_if('b') == Some("b"));
        assert!(strange.pop_char_if('c') == Some("c"));
        assert!(strange.pop_char_if('d') == None);
    }

    #[test]
    fn test_pop_any_of() {
        let mut strange = Strange::new("abc");
        assert!(strange.pop_any_of(&['b', 'a']) == Some("a"));
        assert!(strange.pop_any_of(&['b', 'a']) == Some("b"));
        assert!(strange.pop_any_of(&['b', 'a']) == None);
        assert!(strange.pop_any_of(&['b', 'a', 'c']) == Some("c"));
        assert!(strange.pop_any_of(&['b', 'a', 'c']) == None);
    }

    #[test]
    fn test_pop_until_exc() {
        let mut strange = Strange::new("abc");
        assert!(strange.pop_until_exc('b') == Some("a"));
        assert!(strange.str() == "bc");
    }

    #[test]
    fn test_pop_until_inc() {
        let mut strange = Strange::new("abc");
        assert!(strange.pop_until_inc('b') == Some("ab"));
        assert!(strange.str() == "c");
    }

    #[test]
    fn test_split_first() {
        assert!(split_first("abc") == Some(('a', "a", "bc")));
        assert!(split_first("a") == Some(('a', "a", "")));
        assert!(split_first("") == None);
    }
}
