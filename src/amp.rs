pub mod value;

use crate::{lex, rubr::naft, util};
use std::{collections, fmt::Write};
use tracing::{trace, warn};

pub type Key = String;
pub type Value = value::Value;

#[derive(Debug, Eq, PartialEq, PartialOrd, Ord, Default, Clone)]
pub struct KeyValue {
    pub key: Key,
    pub value: Value,
}

#[derive(Default, Debug, Clone)]
pub struct KVSet {
    pub kvs: collections::BTreeMap<Key, Value>,
}
impl KVSet {
    pub fn new() -> KVSet {
        KVSet::default()
    }
    pub fn is_empty(&self) -> bool {
        self.kvs.is_empty()
    }
    pub fn has(&self, needle: &KeyValue) -> bool {
        for (key, value) in &self.kvs {
            if key == &needle.key {
                match &needle.value {
                    // None works like a wildcard
                    Value::None => return true,
                    // Tag matches with end of the string representation
                    Value::Tag(tag) => return value.to_string().ends_with(tag),
                    _ => return value == &needle.value,
                }
            }
        }
        false
    }
    pub fn for_each(
        &self,
        mut cb: impl FnMut(&Key, &Value) -> util::Result<()>,
    ) -> util::Result<()> {
        for (key, value) in &self.kvs {
            cb(key, value)?;
        }
        Ok(())
    }
    pub fn insert(&mut self, key: &Key, value: &Value) -> Option<Value> {
        self.kvs.insert(key.clone(), value.clone())
    }
    pub fn merge(&mut self, rhs: &KVSet) -> util::Result<()> {
        trace!("Merging");
        rhs.for_each(|k, v| {
            if let Some(value) = self.kvs.get_mut(k) {
                trace!("Calling set_ctx");
                value.set_ctx(v)?;
            } else {
                self.kvs.insert(k.clone(), v.clone());
            }
            Ok(())
        })?;
        Ok(())
    }
    pub fn merge_unless_present(&mut self, rhs: &KVSet) -> util::Result<()> {
        rhs.for_each(|k, v| {
            if !self.kvs.contains_key(k) {
                self.insert(k, v);
            }
            Ok(())
        })?;
        Ok(())
    }
}
impl std::fmt::Display for KVSet {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        for (k, v) in &self.kvs {
            write!(f, " {k}")?;
            if v != &Value::None {
                write!(f, "={}", v)?;
            }
        }
        Ok(())
    }
}
impl naft::ToNaft for KVSet {
    fn to_naft(&self, p: &naft::Node) -> util::Result<()> {
        if !self.is_empty() {
            let n = p.node("KVSet")?;
            for (k, v) in &self.kvs {
                n.attr(k, v)?;
            }
        }
        Ok(())
    }
}

#[derive(Debug, Eq, PartialEq, Clone, Default)]
pub struct Stmt {
    pub range: Range,
    pub kind: Kind,
}

#[derive(Debug, Eq, PartialEq, Clone)]
pub enum Kind {
    Text(String),
    Amp(KeyValue),
}

#[derive(Default)]
pub struct Parser {
    pub stmts: Vec<Stmt>,
    lexer: lex::Lexer,
}

#[derive(PartialEq, Eq, Clone)]
pub enum Match {
    Everywhere,
    OnlyStart,
}

type Range = std::ops::Range<usize>;

impl Default for Kind {
    fn default() -> Kind {
        Kind::Text(String::new())
    }
}

impl std::fmt::Display for KeyValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.value == Value::None {
            write!(f, "{}", &self.key)?;
        } else {
            write!(f, "{}={}", &self.key, &self.value)?;
        }
        Ok(())
    }
}

impl Stmt {
    pub fn new(range: Range, kind: Kind) -> Stmt {
        Stmt { range, kind }
    }

    pub fn write(&self, s: &mut String) -> util::Result<()> {
        match &self.kind {
            Kind::Text(text) => {
                write!(s, "({text})")?;
            }
            Kind::Amp(kv) => {
                let w = |s: &mut String, kv: &KeyValue| -> util::Result<()> {
                    write!(s, "{}", kv)?;
                    Ok(())
                };
                write!(s, "[")?;
                w(s, &kv)?;
                write!(s, "]")?;
            }
        }
        Ok(())
    }
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
                        let mut kv: Option<KeyValue> = None;
                        for token in group.tokens {
                            match token.kind {
                                lex::Kind::Ampersand => {
                                    if kv.is_some() {
                                        todo!("Grouper should produce Groups that match with a single KeyValue");
                                    }
                                    kv = Some(KeyValue::default())
                                }
                                lex::Kind::Equal => {
                                    // &todo &spec: only allow [a-zA-Z_\d] in Key
                                    if let Some(kv) = &mut kv {
                                        match &mut kv.value{
                                            Value::None => {kv.value = Value::Tag(String::new());}
                                            Value::Tag(tag) => {
                                                if let Some(s) = content.get(token.range.clone()) {
                                                    tag.push_str(s);
                                                }
                                            }
                                            _=>unreachable!(),
                                        }
                                    }
                                }
                                _ => {
                                    if let Some(kv) = &mut kv {
                                        if let Some(s) = content.get(token.range.clone()) {
                                            match &mut kv.value{
                                                Value::None => {kv.key.push_str(s);}
                                                Value::Tag(tag) => {
                                                    if let Some(s) = content.get(token.range.clone()) {
                                                        tag.push_str(s);
                                                    }
                                                }
                                                _=>unreachable!(),
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if let Some(kv) = kv {
                            stmt.kind = Kind::Amp(kv);
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
                    lex::Kind::Colon => {
                        // &spec: Group ending on `:` is still Amp, but we move the `:` to the next Group
                        self.token_range.end -= 1;
                    }
                    lex::Kind::Ampersand => {
                        // &spec: Group ending on `&` is still Amp, but we move the `&` to the next Group
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
            (&Match::Everywhere, "todo", "(todo)"),
            (&Match::Everywhere, "&&", "(&&)"),
            (&Match::Everywhere, "a,b", "(a,b)"),
            (&Match::Everywhere, "&nbsp;", "(&nbsp;)"),
            (&Match::Everywhere, "&nbsp;abc", "(&nbsp;)(abc)"),
            (&Match::Everywhere, "&param,", "(&param,)"),
            (&Match::Everywhere, "r&d", "(r&d)"),
            // Metadata
            (&Match::Everywhere, "&todo", "[todo]"),
            (&Match::Everywhere, "&todo:", "[todo](:)"),
            (&Match::Everywhere, "&key=value", "[key=value]"),
            (
                &Match::Everywhere,
                "&key=value,param=vilue",
                "[key=value,param=vilue]",
            ),
            (
                &Match::Everywhere,
                "&key=value&param=vilue",
                "[key=value][param=vilue]",
            ),
            (
                &Match::Everywhere,
                "&key=value &param=vilue",
                "[key=value]( )[param=vilue]",
            ),
            (&Match::Everywhere, "&key=value& abc", "[key=value](& abc)"),
            // Match::OnlyStart
            (&Match::OnlyStart, "abc &def", "(abc &def)"),
            (&Match::OnlyStart, "&abc &def", "[abc]( )[def]"),
        ];

        let mut parser = Parser::new();
        for (m, content, exp) in scns {
            parser.parse(content, m);
            let mut s = String::new();
            for stmt in &parser.stmts {
                stmt.write(&mut s).unwrap();
            }
            assert_eq!(&s, exp)
        }
    }
}
