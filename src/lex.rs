use std::slice::SliceIndex;

#[derive(Debug, Clone)]
pub enum Kind {
    Text,
    Newline,
}

#[derive(Debug, Clone)]
pub struct Token {
    kind: Kind,
    range: std::ops::Range<usize>,
}

impl Token {
    pub fn print(&self, prefix: &str, content: &str) {
        match self.kind {
            Kind::Newline => {
                println!("{prefix}[Token](kind:{:?})", self.kind,)
            }
            _ => println!(
                "{prefix}[Token](kind:{:?})(text:{})",
                self.kind,
                content.get(self.range.clone()).unwrap_or("none")
            ),
        }
    }
}

pub struct Lexer<'a> {
    content: &'a str,
    current: &'a str,
}

impl<'a> Lexer<'a> {
    pub fn new(content: &'a str) -> Lexer<'a> {
        Lexer {
            content,
            current: content,
        }
    }

    pub fn tokenize(&mut self) -> Vec<Token> {
        let mut tokens = Vec::new();
        let mut token: Option<Token> = None;

        for (ix, ch) in self.content.char_indices() {
            match ch {
                // &todo: support all styles of newlines
                '\n' => {
                    if let Some(mut token) = token {
                        token.range.end = ix;
                        tokens.push(token);
                    }
                    token = Some(Token {
                        kind: Kind::Newline,
                        range: ix..ix,
                    });
                }
                _ => match &mut token {
                    None => {
                        token = Some(Token {
                            kind: Kind::Text,
                            range: ix..ix,
                        })
                    }
                    Some(token) => match token.kind {
                        Kind::Text => {}
                        _ => {
                            token.range.end = ix;
                            tokens.push(token.clone());

                            token.kind = Kind::Text;
                            token.range = ix..ix;
                        }
                    },
                },
            }
        }
        if let Some(mut token) = token {
            token.range.end = self.content.len();
            tokens.push(token);
        }

        tokens
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lexing() {
        let content = "line1\nline2";
        let mut lexer = Lexer::new(content);
        let tokens = lexer.tokenize();
        for token in tokens {
            token.print("\t", content);
        }
    }
}
