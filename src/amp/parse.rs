use crate::{amp, fail, lex, util};
use std::fmt::Write;

#[derive(Default)]
pub struct Parser {
    pub stmts: Vec<Stmt>,
    lexer: lex::Lexer,
}

#[derive(Debug, Eq, PartialEq, Clone, Default)]
pub struct Stmt {
    pub range: Range,
    pub kind: Kind,
}

#[derive(Debug, Eq, PartialEq, Clone)]
pub enum Kind {
    Text(String),
    Amp(amp::Path),
}

#[derive(PartialEq, Eq, Clone)]
pub enum Match {
    Everywhere,
    OnlyStart,
}

type Range = std::ops::Range<usize>;

#[derive(Clone, Debug)]
enum State {
    Text,
    Amp,
}

impl std::fmt::Display for State {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            State::Text => write!(f, "Text"),
            State::Amp => write!(f, "Amp"),
        }
    }
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
}

impl std::fmt::Display for Stmt {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match &self.kind {
            Kind::Text(text) => write!(f, "({text})"),
            Kind::Amp(path) => write!(f, "[{}]", path),
        }
    }
}

impl Parser {
    pub fn new() -> Parser {
        Parser::default()
    }

    pub fn parse(&mut self, content: &str, m: &Match) -> util::Result<()> {
        self.stmts.clear();

        self.lexer.tokenize(content);

        let mut grouper = Grouper::new();
        grouper.create_groups(&self.lexer.tokens, m);

        // Translate the Groups into Stmts
        self.stmts = grouper
            .groups
            .iter()
            .map(|group: &Group| -> util::Result<Stmt> {
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
                        let mut range = 0..group.tokens.len();
                        let mut pop = |kind: &lex::Kind| -> bool {
                            if let Some(token) = group.tokens.get(range.start) {
                                if &token.kind == kind {
                                    range.start += 1;
                                    return true;
                                }
                            }
                            return false;
                        };

                        if !pop(&lex::Kind::Ampersand) {
                            fail!("Expected group to start with `&`");
                        }
                        let is_definition = pop(&lex::Kind::Bang);
                        let is_absolute = pop(&lex::Kind::Colon);

                        let mut parts = Vec::<String>::new();
                        let mut part = None;
                        for ix in range {
                            if let Some(token) = group.tokens.get(ix) {
                                match token.kind {
                                    lex::Kind::Colon => match token.range.len() {
                                        // &todo: Support multi-colon
                                        _ => {
                                            if let Some(part) = part {
                                                parts.push(part);
                                            }
                                            part = None;
                                        }
                                    },
                                    _ => {
                                        if let Some(s) = content.get(token.range.clone()) {
                                            if let Some(part) = &mut part {
                                                part.push_str(s);
                                            } else {
                                                part = Some(s.to_owned());
                                            }
                                        }
                                    }
                                }
                            } else {
                                fail!("Could not find Token {ix}");
                            }
                        }
                        if let Some(part) = part {
                            parts.push(part);
                        }

                        let parts = parts
                            .into_iter()
                            .map(|part| amp::Part::Text(part))
                            .collect();
                        let path = amp::Path {
                            is_definition,
                            is_absolute,
                            parts,
                        };
                        stmt.kind = Kind::Amp(path);
                    }
                }

                Ok(stmt)
            })
            .collect::<util::Result<Vec<Stmt>>>()?;

        Ok(())
    }
}

// A sequence of Tokens that can be translated into a Stmt
#[derive(Debug)]
struct Group<'a> {
    state: State,
    tokens: &'a [lex::Token],
}

impl<'a> std::fmt::Display for Group<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "[Group](state:{})", &self.state)?;
        for token in self.tokens.iter() {
            write!(f, "{token}")?;
        }
        Ok(())
    }
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
        let mut m: Match = m.clone();
        for token in tokens {
            match self.state {
                State::Text => {
                    if token.kind == lex::Kind::Ampersand
                        && token.range.len() == 1
                        && (is_first || m == Match::Everywhere)
                        // &spec: ampersand can only start Amp at start or after a space
                        && last_was_space
                    {
                        self.start_new_group(State::Amp, tokens);
                        // &spec: as soon as we found a match, we allow matches everywhere
                        m = Match::Everywhere;
                    }
                    self.token_range.end += 1;
                }
                State::Amp => match token.kind {
                    lex::Kind::Ampersand => {
                        self.start_new_group(State::Amp, tokens);
                        self.token_range.end += 1;
                    }
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
            (&Match::Everywhere, "todo", "(todo)"),
            (&Match::Everywhere, "&&", "(&&)"),
            (&Match::Everywhere, "a,b", "(a,b)"),
            (&Match::Everywhere, "&nbsp;", "(&nbsp;)"),
            (&Match::Everywhere, "&nbsp;abc", "(&nbsp;)(abc)"),
            (&Match::Everywhere, "&param,", "(&param,)"),
            (&Match::Everywhere, "r&d", "(r&d)"),
            // Metadata
            (&Match::Everywhere, "&todo", "[todo]"),
            (&Match::Everywhere, "&todo:", "[todo]"),
            (
                &Match::Everywhere,
                "&!:prio:~priority",
                "[!:prio:~priority]",
            ),
        ];

        let mut parser = Parser::new();
        for (m, content, exp) in scns {
            parser.parse(content, m);
            let mut s = String::new();
            for stmt in &parser.stmts {
                write!(&mut s, "{stmt}").unwrap();
            }
            assert_eq!(&s, exp)
        }
    }
}
