use crate::{fail, lex, util};

type Token = lex::Token;
type Kind = lex::Kind;
type Range = std::ops::Range<usize>;

#[derive(Debug)]
pub struct Node {
    pub line_ix: u64,
    pub range: Range,
    pub comment: bool,
    pub childs: Vec<usize>,
}

#[derive(Debug)]
struct Comment {
    kind: Kind,
    count: usize,
}

#[derive(Debug)]
pub struct Tree {
    pub nodes: Vec<Node>,
    delim: Comment,
}

impl Tree {
    pub fn new(comment: &str) -> util::Result<Tree> {
        let mut kind = None;
        for ch in comment.chars() {
            let k = Kind::from(ch);
            if k == Kind::Text {
                fail!("The comment Kind should not be Text");
            }
            if let Some(kind) = &kind {
                if &k != kind {
                    fail!("Kind {:?} is different from {:?}", k, kind);
                }
            } else {
                kind = Some(k);
            }
        }

        match kind {
            None => fail!("Could not determine comment Kind"),
            Some(kind) => {
                let mut tree = Tree {
                    nodes: Vec::new(),
                    delim: Comment {
                        kind,
                        count: comment.len(),
                    },
                };
                tree.init_only_root();
                Ok(tree)
            }
        }
    }

    pub fn init(&mut self, tokens: &[Token]) {
        self.init_only_root();

        let mut state = State::Idle;
        for token in tokens {
            if token.kind == Kind::Newline {
                state = State::Idle;
            } else {
                if state == State::Idle {
                    // Create Code node and hook it under Root
                    let ix = self.nodes.len();
                    let node = Node {
                        line_ix: token.line_ix,
                        range: token.range.clone(),
                        comment: false,
                        childs: Vec::new(),
                    };
                    self.nodes.push(node);
                    self.root().childs.push(ix);

                    state = State::Code;
                }

                match state {
                    State::Code => {
                        if token.kind == self.delim.kind && token.range.len() == self.delim.count {
                            state = State::Delim;
                        }
                    }
                    State::Delim => {
                        if token.kind != Kind::Space {
                            let ix = self.nodes.len();
                            let node = Node {
                                line_ix: token.line_ix,
                                range: token.range.clone(),
                                comment: true,
                                childs: Vec::new(),
                            };
                            self.nodes.push(node);
                            self.root().childs.push(ix);

                            state = State::Comment;
                        }
                    }
                    _ => {}
                }

                // Append token to last()
                {
                    let node = self.last();
                    node.range.end = token.range.end;
                }
            }
        }
    }

    pub fn print(&self, content: &str) -> String {
        let mut s = String::new();
        self.print_(&self.nodes[0], &mut s, content);
        s
    }
    fn print_(&self, node: &Node, s: &mut String, content: &str) {
        s.push_str("(");
        if let Some(body) = content.get(node.range.clone()) {
            s.push_str(body);
        }
        for &child_ix in &node.childs {
            // println!("child_ix: {child_ix}");
            self.print_(&self.nodes[child_ix], s, content);
        }
        s.push_str(")");
    }

    fn root(&mut self) -> &mut Node {
        &mut self.nodes[0]
    }
    fn init_only_root(&mut self) {
        self.nodes.clear();
        self.nodes.push(Node {
            line_ix: 0,
            range: 0..0,
            comment: false,
            childs: Vec::new(),
        });
    }
    fn last(&mut self) -> &mut Node {
        self.nodes.last_mut().unwrap()
    }
}

#[derive(PartialEq, Eq)]
enum State {
    Idle,
    Code,
    Delim,
    Comment,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tree() -> util::Result<()> {
        let scns = [
            ("//", "code // comment", "((code // )(comment))"),
            ("#", "code # comment", "((code # )(comment))"),
            (
                "#",
                "a#b\nc#d#e\nf\n#g\n\nh",
                "((a#)(b)(c#)(d#e)(f)(#)(g)(h))",
            ),
        ];

        let mut lexer = lex::Lexer::new();

        for (comment, content, exp) in scns {
            println!("content: {content}");
            lexer.tokenize(content);

            let mut tree = Tree::new(comment)?;
            tree.init(&lexer.tokens);
            println!("{:?}", &tree);

            assert_eq!(tree.print(content), exp);
        }

        Ok(())
    }
}
