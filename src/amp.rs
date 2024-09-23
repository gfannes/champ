use crate::{strange, util};
use static_assertions::const_assert;

pub type KV = (String, Option<String>);
pub type KVs = Vec<KV>;

#[derive(Debug, Eq, PartialEq, PartialOrd, Ord, Default)]
pub struct Metadata {
    kv: KV,
    params: KVs,
}

#[derive(Debug, Eq, PartialEq, PartialOrd, Ord)]
pub enum Statement {
    String(String),
    Metadata(Metadata),
}

impl From<&str> for Statement {
    fn from(str: &str) -> Self {
        Statement::String(str.to_owned())
    }
}
impl<const N: usize> From<[(&str, Option<&str>); N]> for Statement {
    fn from(kvs: [(&str, Option<&str>); N]) -> Self {
        println!("N: {}", N);
        assert!(N >= 1);

        let first = kvs[0];
        let mut md = Metadata {
            kv: (first.0.to_owned(), first.1.map(|str| str.to_owned())),
            ..Default::default()
        };
        for kv in &kvs[1..] {
            let kv = (kv.0.to_owned(), kv.1.map(|str| str.to_owned()));
            md.params.push(kv);
        }
        Statement::Metadata(md)
    }
}

pub type Statements = Vec<Statement>;

pub fn parse(content: &str) -> Statements {
    let mut ret = Statements::new();
    let mut strange = strange::Strange::new(content);
    while !strange.is_empty() {
        if strange.read_char_if('&') {
            strange.drop();
            let mut part = strange.read_until_exc(' ');
            if part.is_none() {
                part = strange.read_all();
            }
            if let Some(s) = part {
                ret.push(Statement::from([(s, None)]));
            }
        } else {
            let mut part = strange.read_until_exc(' ');
            if part.is_none() {
                part = strange.read_all();
            }
            if let Some(s) = part {
                ret.push(Statement::from(s));
            }
        }
    }
    ret
}

pub struct Parser {}

impl Parser {
    pub fn new(content: &str) -> Parser {
        Parser {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_statement() {
        let md = Statement::from([("todo", None)]);
    }

    #[test]
    fn test_parse() {
        let scns = [
            ("todo", vec![Statement::from("todo")]),
            ("&todo", vec![Statement::from([("todo", None)])]),
        ];

        for scn in scns {
            let stmts = parse(scn.0);
            assert_eq!(stmts, scn.1);
        }
    }
}
