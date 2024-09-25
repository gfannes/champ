use crate::{strange, util};

#[derive(Default, Debug)]
struct Node {
    range: Range,
    childs: Vec<usize>,
}

#[derive(Default, Debug)]
struct Tree {
    nodes: Vec<Node>,
    headers: Vec<usize>,
    bullets: Vec<usize>,
}
impl Tree {
    fn init(&mut self, tokens: &[Token]) {
        self.nodes.clear();
        self.headers.clear();
        self.bullets.clear();

        let root_ix = self.append(Node::default());
        self.headers.push(root_ix);

        let mut is_new_line = true;
        let mut is_header = false;
        for token in tokens {
            if token.kind == Kind::Newline {
                is_new_line = true;
                is_header = false;
                self.bullets.clear();
            } else if is_new_line {
                match token.kind {
                    Kind::Hash => {
                        let level = len(&token.range);
                        assert!(level > 0);
                        // Drop all headers that are nested deeper
                        while self.headers.len() > level {
                            self.headers.pop();
                        }
                        // Create missing headers
                        while self.headers.len() <= level {
                            let node = Node::default();
                            let ix = self.append(node);
                            self.header().childs.push(ix);
                            self.headers.push(ix);
                        }
                        let header = self.header();
                        header.range = token.range.clone();

                        is_header = true;
                    }
                    _ => {
                        let bullet = self.bullet();
                        bullet.range = token.range.clone();
                    }
                }
                is_new_line = false;
            } else {
                if is_header {
                    let header = self.header();
                    header.range.end = token.range.end;
                } else {
                    let bullet = self.bullet();
                    bullet.range.end = token.range.end;
                }
            }
        }
    }

    fn print(&self, content: &str) -> String {
        let mut s = String::new();
        if let Some(root) = self.nodes.get(0) {
            self.print_(root, &mut s, content);
        }
        s
    }
    fn print_(&self, node: &Node, os: &mut String, content: &str) {
        os.push_str("(");
        if let Some(s) = content.get(node.range.clone()) {
            os.push_str(s);
        }
        for child in &node.childs {
            os.push_str(" ");
            self.print_(&self.nodes[*child], os, content);
        }
        os.push_str(")");
    }

    fn header(&mut self) -> &mut Node {
        let ix = self.headers.last().unwrap();
        &mut self.nodes[*ix]
    }
    fn bullet(&mut self) -> &mut Node {
        if self.bullets.is_empty() {
            let ix = self.append(Node::default());
            self.header().childs.push(ix);
            self.bullets.push(ix);
        }
        let ix = self.bullets.last().unwrap();
        &mut self.nodes[*ix]
    }

    fn append(&mut self, node: Node) -> usize {
        let ix = self.nodes.len();
        self.nodes.push(node);
        ix
    }
}
fn len(range: &Range) -> usize {
    range.end - range.start
}

type Range = std::ops::Range<usize>;

#[derive(Debug, PartialEq, Eq, Clone)]
struct Token {
    kind: Kind,
    range: Range,
    line: u64,
}
impl Token {
    fn new(kind: Kind, range: Range, line: u64) -> Token {
        Token { kind, range, line }
    }
}

#[derive(Debug, PartialEq, Eq, Clone)]
enum Kind {
    Idle,
    Hash,
    Space,
    Dash,
    Star,
    Backtick,
    Dollar,
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
            '\n' | '\r' => Kind::Newline,
            _ => Kind::Text,
        }
    }
}

#[derive(Default)]
struct Lexer {
    tokens: Vec<Token>,
}
impl Lexer {
    pub fn tokenize(&mut self, content: &str) -> util::Result<()> {
        self.tokens.clear();

        let mut line: u64 = 0;
        let mut current = Token {
            kind: Kind::Idle,
            range: 0..0,
            line,
        };
        let mut strange = strange::Strange::new(content);
        while let Some(ch) = strange.try_read_char() {
            if ch == '\n' {
                match current.kind {
                    Kind::Idle => {
                        self.tokens.push(Token::new(
                            Kind::Newline,
                            current.range.end..strange.index(),
                            line,
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
                            line,
                        ));
                    }
                }

                line += 1;
                current = Token {
                    kind: Kind::Idle,
                    range: strange.index()..strange.index(),
                    line,
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
                        line,
                    };
                }
            }
        }
        if current.kind != Kind::Idle {
            self.tokens.push(current);
        }

        Ok(())
    }
}

#[derive(Default, PartialEq, Eq, Debug)]
struct Line {
    all: Range,
    main: Range,
}
type Lines = Vec<Line>;
impl Line {
    pub fn new(all: Range, main: Range) -> Line {
        Line { all, main }
    }
}

fn split_lines(str: &str) -> Lines {
    let mut lines = Vec::new();

    let mut strange = strange::Strange::new(str);

    while !strange.is_empty() {
        strange.save();
        strange.read(|r| r.exclude().to_end().until('\n'));
        let mut main = strange.pop_range();
        let all = main.start..main.end + strange.read_char_if('\n') as usize;

        let mut strange = strange::Strange::new(str.get(main.clone()).unwrap());
        while strange.read_char_when(|ch| " \t#-*$`".contains(ch)) {
            main.start += 1;
        }
        lines.push(Line { all, main });
    }

    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tree() -> util::Result<()> {
        let scns = [
            ("", "()"),
            ("# Title", "( (# Title))"),
            ("# Title\nLine1\nLine2", "( (# Title (Line1) (Line2)))"),
            (
                "# T1\nL1\nL2\n# T2\nL3\nL4",
                "( (# T1 (L1) (L2)) (# T2 (L3) (L4)))",
            ),
        ];
        let mut lexer = Lexer::default();

        for (content, exp) in scns {
            lexer.tokenize(content)?;

            let mut tree = Tree::default();
            tree.init(&lexer.tokens);

            assert_eq!(&tree.print(content), exp);
        }

        Ok(())
    }

    #[test]
    fn test_tokenize() -> util::Result<()> {
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

        let mut lexer = Lexer::default();
        for (content, exp) in scns {
            lexer.tokenize(content)?;
            assert_eq!(&lexer.tokens, &exp);
        }

        Ok(())
    }

    #[test]
    fn test_split_lines() {
        let scns = [
            ("\n", vec![Line::new(0..1, 0..0)]),
            ("\n\n", vec![Line::new(0..1, 0..0), Line::new(1..2, 1..1)]),
            ("Line", vec![Line::new(0..4, 0..4)]),
            (" Space", vec![Line::new(0..6, 1..6)]),
            ("# Title", vec![Line::new(0..7, 2..7)]),
            (
                "# Title\nLine",
                vec![Line::new(0..8, 2..7), Line::new(8..12, 8..12)],
            ),
        ];

        for (scn, exp) in scns {
            let lines = split_lines(scn);
            assert_eq!(lines, exp);
        }
    }
}
