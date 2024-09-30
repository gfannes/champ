use crate::{lex, rubr::strange};
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
        println!("groups: {:?}", &grouper.groups);

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
                    State::Amp => {}
                };
                stmt
            })
            .collect();

        println!("stmts: {:?}", &self.stmts);
    }

    pub fn parse_(&mut self, content: &str, m: &Match) {
        self.stmts.clear();

        let mut strange = strange::Strange::new(content);

        if m == &Match::OnlyStart {
            if !strange.read_char_if('&') {
                return;
            }
            strange.reset();
        }

        while !strange.is_empty() {
            strange.save();
            if strange.read_char_if('&') {
                if let Some(s) = strange.read(|r| r.to_end().exclude().through(' ')) {
                    if match s.chars().next() {
                        Some('&') | Some('\\') | Some('=') => true,
                        _ => false,
                    } || s.starts_with("nbsp")
                        || match s.chars().next_back() {
                            Some(';') | Some(',') => true,
                            _ => false,
                        }
                    {
                    } else {
                        let mut strange = strange::Strange::new(s);
                        strange.unwrite_char_if(':');
                        // &todo: support AMP parameters: add while loop
                        if let Some(key) = strange
                            .read(|r| r.to_end().exclude().through('='))
                            .map(|s| s.to_owned())
                        {
                            let value = (!strange.is_empty()).then(|| strange.to_string());
                            self.stmts.push(Stmt::new(
                                strange.pop_range(),
                                Kind::Amp(Amp {
                                    kv: KeyValue { key, value },
                                    params: Vec::new(),
                                }),
                            ));
                        }
                        continue;
                    }
                }
            }
            strange.reset();

            if let Some(s) = strange
                .read(|r| r.to_end().exclude().through(' '))
                .map(|s| s.to_owned())
            {
                self.stmts
                    .push(Stmt::new(strange.pop_range(), Kind::Text(s)));
            }
        }
    }
}

// A sequence of Tokens that can be translated into a Stmt
#[derive(Debug)]
struct Group<'a> {
    state: State,
    tokens: &'a [lex::Token],
}

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
        for token in tokens {
            println!(
                "state: {:?}, token: {:?}, token_range: {:?}",
                self.state, token, &self.token_range
            );
            match self.state {
                State::Text => {
                    if token.kind == lex::Kind::Ampersand
                        && token.range.len() == 1
                        && (is_first || m == &Match::Everywhere)
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
                    lex::Kind::Semicolon | lex::Kind::Comma => {
                        self.state = State::Text;
                        self.token_range.end += 1;
                        self.start_new_group(State::Text, tokens);
                    }
                    _ => {
                        self.token_range.end += 1;
                    }
                },
            }
            is_first = false;
        }
        self.start_new_group(State::Text, tokens);
    }

    fn start_new_group(&mut self, state: State, tokens: &'a [lex::Token]) {
        let ix = self.token_range.end;

        if !self.token_range.is_empty() {
            self.groups.push(Group::<'a> {
                state: self.state.clone(),
                tokens: &tokens[self.token_range.clone()],
            });
        }

        self.state = state;
        self.token_range = ix..ix;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse() {
        // &todo: rework into exp with String
        let scns = [
            // String
            // ("todo", "(todo)"),
            // ("&&", "(&&)"),
            // ("a,b", "(a,b)"),
            ("&nbsp;", "(&nbsp;)"),
            // &fixme
            ("&nbsp;abc", "(&nbsp;abc)"),
            ("&param,", "(&param,)"),
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
