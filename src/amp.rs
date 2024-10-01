use crate::{lex, rubr::strange, util};
use std::fmt::Write;

pub type Key = String;
pub type Value = Option<String>;
pub type Range = std::ops::Range<usize>;

#[derive(Debug, Eq, PartialEq, PartialOrd, Ord, Default, Clone)]
pub struct KeyValue {
    pub key: Key,
    pub value: Value,
}

#[derive(Debug, Eq, PartialEq, Clone, Default)]
pub struct Stmt {
    pub range: Range,
    pub kind: Kind,
}

#[derive(Debug, Eq, PartialEq, PartialOrd, Ord, Default, Clone)]
pub struct Amp {
    pub kv: KeyValue,
    pub params: Vec<KeyValue>,
}

#[derive(Debug, Eq, PartialEq, Clone)]
pub enum Kind {
    Text(String),
    Amp(Amp),
}
impl Default for Kind {
    fn default() -> Kind {
        Kind::Text(String::new())
    }
}

impl Stmt {
    pub fn new(range: Range, kind: Kind) -> Stmt {
        Stmt { range, kind }
    }

    pub fn write(&self, s: &mut String) {
        match &self.kind {
            Kind::Text(text) => {
                write!(s, "({text})");
            }
            Kind::Amp(amp) => {
                let w = |s: &mut String, kv: &KeyValue| {
                    write!(s, "{}", kv.key);
                    if let Some(value) = &kv.value {
                        write!(s, "={value}");
                    }
                };
                write!(s, "[");
                w(s, &amp.kv);
                for param in &amp.params {
                    write!(s, ",");
                    w(s, param);
                }
                write!(s, "]");
            }
        }
    }
}

#[derive(Default)]
pub struct Parser {
    pub stmts: Vec<Stmt>,
    lexer: lex::Lexer,
}

#[derive(PartialEq, Eq)]
pub enum Match {
    Everywhere,
    OnlyStart,
}

#[derive(Clone, Debug)]
enum State {
    Text,
    Amp,
}

impl Parser {
    pub fn new() -> Parser {
        Parser::default()
    }
    pub fn parse(&mut self, content: &str, m: &Match) {
        self.stmts.clear();

        self.lexer.tokenize(content);

        let mut grouper = Grouper::new();
        grouper.create_groups(&self.lexer.tokens, m);

        // Translate the Groups into Stmts
        self.stmts = grouper
            .groups
            .iter()
            .map(|group| {
                let mut stmt = Stmt::default();

                if let Some(token) = group.tokens.first() {
                    stmt.range = token.range.clone();
                }
                if let Some(token) = group.tokens.last() {
                    stmt.range.end = token.range.end;
                }

                match group.state {
                    State::Text => {
                        let s = content.get(stmt.range.clone()).unwrap_or_else(|| "");
                        stmt.kind = Kind::Text(s.into());
                    }
                    State::Amp => {
                        let mut amp: Option<Amp> = None;
                        let mut kv = None;
                        for token in group.tokens {
                            match token.kind {
                                lex::Kind::Ampersand | lex::Kind::Comma => {
                                    if let Some(kv) = kv {
                                        if let Some(amp) = &mut amp {
                                            amp.params.push(kv);
                                        } else {
                                            amp = Some(Amp {
                                                kv,
                                                ..Default::default()
                                            });
                                        }
                                    }
                                    kv = Some(KeyValue::default())
                                }
                                lex::Kind::Equal => {
                                    if let Some(kv) = &mut kv {
                                        if let Some(v) = &mut kv.value {
                                            if let Some(s) = content.get(token.range.clone()) {
                                                v.push_str(s);
                                            }
                                        } else {
                                            kv.value = Some(String::new());
                                        }
                                    }
                                }
                                _ => {
                                    if let Some(kv) = &mut kv {
                                        if let Some(s) = content.get(token.range.clone()) {
                                            if let Some(v) = &mut kv.value {
                                                v.push_str(s);
                                            } else {
                                                kv.key.push_str(s);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if let Some(kv) = kv {
                            if let Some(amp) = &mut amp {
                                amp.params.push(kv);
                            } else {
                                amp = Some(Amp {
                                    kv,
                                    ..Default::default()
                                });
                            }
                        }
                        if let Some(amp) = amp {
                            stmt.kind = Kind::Amp(amp);
                        }
                    }
                };

                stmt
            })
            .collect();
    }
}

// A sequence of Tokens that can be translated into a Stmt
#[derive(Debug)]
struct Group<'a> {
    state: State,
    tokens: &'a [lex::Token],
}

// Groups a sequence of Tokens into Groups that can be easily translated into a Stmt
struct Grouper<'a> {
    state: State,
    token_range: Range,
    groups: Vec<Group<'a>>,
}

impl<'a> Grouper<'a> {
    fn new() -> Grouper<'a> {
        Grouper {
            state: State::Text,
            token_range: 0..0,
            groups: Vec::new(),
        }
    }
    fn reset(&mut self) {
        self.state = State::Text;
        self.token_range = 0..0;
        self.groups.clear();
    }

    fn create_groups(&mut self, tokens: &'a [lex::Token], m: &Match) {
        self.reset();

        let mut is_first = true;
        let mut last_was_space = true;
        for token in tokens {
            match self.state {
                State::Text => {
                    if token.kind == lex::Kind::Ampersand
                        && token.range.len() == 1
                        && (is_first || m == &Match::Everywhere)
                        // &spec: ampersand can only start Amp at start or after a space
                        && last_was_space
                    {
                        self.start_new_group(State::Amp, tokens);
                    }
                    self.token_range.end += 1;
                }
                State::Amp => match token.kind {
                    lex::Kind::Space => {
                        self.start_new_group(State::Text, tokens);
                        self.token_range.end += 1;
                    }
                    lex::Kind::Semicolon => {
                        // &spec: a semicolon is cannot occur in Amp.
                        // &todo: make this more precise: an Amp cannot _end_ with a semicolon
                        self.state = State::Text;
                        self.token_range.end += 1;
                        self.start_new_group(State::Text, tokens);
                    }
                    _ => {
                        self.token_range.end += 1;
                    }
                },
            }
            last_was_space = token.kind == lex::Kind::Space;
            is_first = false;
        }
        // Might require more than one additional group at the end, eg, if content ends with `@todo:`:
        // - The `:` is splitted last-minute into a new group
        while !self.token_range.is_empty() {
            self.start_new_group(State::Text, tokens);
        }
    }

    fn start_new_group(&mut self, state: State, tokens: &'a [lex::Token]) {
        let end = self.token_range.end;

        while !self.token_range.is_empty() {
            let tokens = &tokens[self.token_range.clone()];

            let mut push_group = || {
                self.groups.push(Group::<'a> {
                    state: self.state.clone(),
                    tokens,
                });
                self.token_range.start = self.token_range.end;
            };

            match self.state {
                State::Text => push_group(),
                State::Amp => match tokens.last().unwrap().kind {
                    lex::Kind::Colon => {
                        // &spec: Group ending on `:` is still Amp, but we move the `:` to the next Group
                        self.token_range.end -= 1;
                    }
                    lex::Kind::Ampersand => {
                        // &spec: Group ending on `&` is still Amp, but we move the `:` to the next Group
                        self.token_range.end -= 1;
                    }
                    lex::Kind::Semicolon | lex::Kind::Comma => {
                        // &spec: Group ending on `;` or `,` is considered as Text
                        // - &nbsp; occurs ofter in Markdown and is considered a false positive
                        // - &param, occurs in commented-out C/C++/Rust source code
                        self.state = State::Text;
                    }
                    _ => push_group(),
                },
            }
        }

        self.state = state;
        self.token_range.end = end;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse() {
        let scns = [
            // String
            ("todo", "(todo)"),
            ("&&", "(&&)"),
            ("a,b", "(a,b)"),
            ("&nbsp;", "(&nbsp;)"),
            ("&nbsp;abc", "(&nbsp;)(abc)"),
            ("&param,", "(&param,)"),
            ("r&d", "(r&d)"),
            // Metadata
            ("&todo", "[todo]"),
            ("&todo:", "[todo](:)"),
            ("&key=value", "[key=value]"),
            ("&key=value,param=vilue", "[key=value,param=vilue]"),
        ];

        let mut parser = Parser::new();
        for (content, exp) in scns {
            parser.parse(content, &Match::Everywhere);
            let mut s = String::new();
            for stmt in &parser.stmts {
                stmt.write(&mut s);
            }
            assert_eq!(&s, exp)
        }
    }
}
