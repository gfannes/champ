use crate::strange;

pub type KV = (String, Option<String>);
pub type KVs = Vec<KV>;

#[derive(Debug, Eq, PartialEq, PartialOrd, Ord, Default)]
pub struct Metadata {
    pub kv: KV,
    pub params: KVs,
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

#[derive(Default)]
pub struct Parser {
    pub stmts: Statements,
}

impl Parser {
    pub fn new() -> Parser {
        Parser::default()
    }
    pub fn parse(&mut self, content: &str) {
        self.stmts.clear();

        let mut strange = strange::Strange::new(content);
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
                        if let Some(key) = strange.read(|r| r.to_end().exclude().through('=')) {
                            let value = (!strange.is_empty()).then(|| strange.to_str());
                            self.stmts.push(Statement::from([(key, value)]));
                        }
                        continue;
                    }
                }
            }
            strange.reset();

            if let Some(s) = strange.read(|r| r.to_end().exclude().through(' ')) {
                self.stmts.push(Statement::from(s));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_statement() {
        let md = Statement::from([("todo", None)]);
        assert_eq!(
            md,
            Statement::Metadata(Metadata {
                kv: ("todo".to_owned(), None),
                ..Default::default()
            })
        )
    }

    #[test]
    fn test_parse() {
        let scns = [
            // String
            ("todo", vec![Statement::from("todo")]),
            ("&&", vec![Statement::from("&&")]),
            ("&nbsp;", vec![Statement::from("&nbsp;")]),
            // &fixme
            ("&nbsp;abc", vec![Statement::from("&nbsp;abc")]),
            ("&param,", vec![Statement::from("&param,")]),
            // Metadata
            ("&todo", vec![Statement::from([("todo", None)])]),
            ("&todo:", vec![Statement::from([("todo", None)])]),
            (
                "&key=value",
                vec![Statement::from([("key", Some("value"))])],
            ),
            (
                "&key=value,param=vilue",
                vec![Statement::from([("key", Some("value,param=vilue"))])],
                // &todo: parse parameters
                // vec![Statement::from([
                //     ("key", Some("value")),
                //     ("param", Some("vilue")),
                // ])],
            ),
        ];

        let mut parser = Parser::new();
        for scn in scns {
            parser.parse(scn.0);
            assert_eq!(parser.stmts, scn.1);
        }
    }
}
