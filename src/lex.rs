use crate::rubr::strange;
use std::fmt::Write;

#[derive(Debug, PartialEq, Eq, Clone)]
pub struct Token {
    pub kind: Kind,
    pub range: Range,
    pub line_ix: u64,
}

#[derive(Default)]
pub struct Lexer {
    pub tokens: Vec<Token>,
}

type Range = std::ops::Range<usize>;

impl Token {
    fn new(kind: Kind, range: Range, line_ix: u64) -> Token {
        Token {
            kind,
            range,
            line_ix,
        }
    }
}

impl std::fmt::Display for Token {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "[Token](kind:{})", self.kind)
    }
}

impl std::fmt::Display for Kind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Kind::Idle => write!(f, "Idle"),
            Kind::Hash => write!(f, "Hash"),
            Kind::Space => write!(f, "Space"),
            Kind::Dash => write!(f, "Dash"),
            Kind::Star => write!(f, "Star"),
            Kind::Backtick => write!(f, "Backtick"),
            Kind::Dollar => write!(f, "Dollar"),
            Kind::Slash => write!(f, "Slash"),
            Kind::Ampersand => write!(f, "Ampersand"),
            Kind::Colon => write!(f, "Colon"),
            Kind::Semicolon => write!(f, "Semicolon"),
            Kind::Comma => write!(f, "Comma"),
            Kind::Equal => write!(f, "Equal"),
            Kind::Bang => write!(f, "Bang"),
            Kind::Tilde => write!(f, "Tilde"),
            Kind::Text => write!(f, "Text"),
            Kind::Newline => write!(f, "Newline"),
        }
    }
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum Kind {
    Idle,
    Hash,
    Space,
    Dash,
    Star,
    Backtick,
    Dollar,
    Slash,
    Ampersand,
    Colon,
    Semicolon,
    Comma,
    Equal,
    Bang,
    Tilde,
    Text,
    Newline,
}
impl From<char> for Kind {
    fn from(ch: char) -> Kind {
        match ch {
            '#' => Kind::Hash,
            ' ' => Kind::Space,
            '-' => Kind::Dash,
            '*' => Kind::Star,
            '`' => Kind::Backtick,
            '$' => Kind::Dollar,
            '/' => Kind::Slash,
            '&' => Kind::Ampersand,
            ':' => Kind::Colon,
            ';' => Kind::Semicolon,
            ',' => Kind::Comma,
            '=' => Kind::Equal,
            '!' => Kind::Bang,
            '~' => Kind::Tilde,
            '\n' | '\r' => Kind::Newline,
            _ => Kind::Text,
        }
    }
}

impl Lexer {
    pub fn new() -> Lexer {
        Lexer::default()
    }
    pub fn tokenize(&mut self, content: &str) {
        self.tokens.clear();

        let mut line_ix: u64 = 0;
        let mut current = Token {
            kind: Kind::Idle,
            range: 0..0,
            line_ix,
        };
        let mut strange = strange::Strange::new(content);
        while let Some(ch) = strange.try_read_char() {
            if ch == '\n' {
                match current.kind {
                    Kind::Idle => {
                        self.tokens.push(Token::new(
                            Kind::Newline,
                            current.range.end..strange.index(),
                            line_ix,
                        ));
                    }
                    Kind::Newline => {
                        current.range.end = strange.index();
                        self.tokens.push(current);
                    }
                    _ => {
                        let new_start = current.range.end;
                        self.tokens.push(current);
                        self.tokens.push(Token::new(
                            Kind::Newline,
                            new_start..strange.index(),
                            line_ix,
                        ));
                    }
                }

                line_ix += 1;
                current = Token {
                    kind: Kind::Idle,
                    range: strange.index()..strange.index(),
                    line_ix,
                };
            } else {
                let kind = Kind::from(ch);
                if kind == current.kind {
                    // Same token kind: extend the range
                    current.range.end = strange.index();
                } else {
                    // Different token kind: push the previous token and start a new one
                    let new_start = current.range.end;
                    if current.kind != Kind::Idle {
                        self.tokens.push(current);
                    }
                    current = Token {
                        kind,
                        range: new_start..strange.index(),
                        line_ix,
                    };
                }
            }
        }
        if current.kind != Kind::Idle {
            self.tokens.push(current);
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tokenize() {
        let scns = [
            ("", vec![]),
            ("#", vec![Token::new(Kind::Hash, 0..1, 0)]),
            ("##", vec![Token::new(Kind::Hash, 0..2, 0)]),
            ("abc", vec![Token::new(Kind::Text, 0..3, 0)]),
            (
                "## Title",
                vec![
                    Token::new(Kind::Hash, 0..2, 0),
                    Token::new(Kind::Space, 2..3, 0),
                    Token::new(Kind::Text, 3..8, 0),
                ],
            ),
            ("\n", vec![Token::new(Kind::Newline, 0..1, 0)]),
            ("\r\n", vec![Token::new(Kind::Newline, 0..2, 0)]),
            (
                "\n\n",
                vec![
                    Token::new(Kind::Newline, 0..1, 0),
                    Token::new(Kind::Newline, 1..2, 1),
                ],
            ),
            (
                "\n\r\n\r\r\n",
                vec![
                    Token::new(Kind::Newline, 0..1, 0),
                    Token::new(Kind::Newline, 1..3, 1),
                    Token::new(Kind::Newline, 3..6, 2),
                ],
            ),
        ];

        let mut lexer = Lexer::new();
        for (content, exp) in scns {
            lexer.tokenize(content);
            assert_eq!(&lexer.tokens, &exp);
        }
    }
}
