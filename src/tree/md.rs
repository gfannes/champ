use crate::{lex, tree};

#[derive(Default, Debug)]
pub struct Tree {
    // Tree data itself
    pub nodes: Vec<Node>,

    // Used during Tree.init()
    headers: Vec<usize>,
    bullets: Vec<usize>,
    codeblock: Option<usize>,
    formulablock: Option<usize>,
    state: State,
    prev_state: State,
}

#[derive(Default, Debug)]
pub struct Node {
    pub line_ix: u64,
    pub parts: Vec<Part>,
    pub childs: Vec<usize>,
}

type Part = tree::Part;

#[derive(Debug, Clone)]
enum State {
    Idle,
    Header,
    Bullet,
    Code,
    CodeBlock,
    Formula,
    FormulaBlock,
}
impl Default for State {
    fn default() -> State {
        State::Idle
    }
}

type Token = lex::Token;

impl Tree {
    pub fn new() -> Tree {
        Tree::default()
    }

    pub fn init(&mut self, tokens: &[Token]) {
        self.nodes.clear();
        self.headers.clear();
        self.bullets.clear();

        let root_ix = self.append(Node::default());
        self.headers.push(root_ix);

        self.state = State::Idle;
        for token in tokens {
            match self.state {
                State::Idle => {
                    if false {
                    } else if self.handle_newline(token) {
                    } else if self.handle_backtick(token) {
                    } else if self.handle_dollar(token) {
                    } else {
                        match token.kind {
                            lex::Kind::Hash => {
                                self.bullets.clear();

                                let level = token.range.len();
                                assert!(level > 0);
                                // Drop all headers that are nested deeper
                                while self.headers.len() > level {
                                    self.headers.pop();
                                }
                                // Create missing headers
                                while self.headers.len() <= level {
                                    let node = Node::new(token.line_ix);
                                    let ix = self.append(node);
                                    self.header().childs.push(ix);
                                    self.headers.push(ix);
                                }
                                let header = self.header();
                                header.parts.push(Part::new(&token.range, tree::Kind::Data));

                                self.state = State::Header;
                            }
                            lex::Kind::Dash | lex::Kind::Star => {
                                let level = token.range.len();
                                assert!(level > 0);
                                // Drop all bullets that are nested deeper
                                while self.bullets.len() > level {
                                    self.bullets.pop();
                                }
                                // Create missing bullets
                                while self.bullets.len() <= level {
                                    let node = Node::new(token.line_ix);
                                    let ix = self.append(node);
                                    self.bullet().childs.push(ix);
                                    self.bullets.push(ix);
                                }
                                let bullet = self.bullet();
                                bullet.parts.push(Part::new(&token.range, tree::Kind::Data));

                                self.state = State::Bullet;
                            }
                            _ => {
                                let mut node = Node::new(token.line_ix);
                                node.parts.push(Part::new(&token.range, tree::Kind::Meta));
                                let ix = self.append(node);
                                self.header().childs.push(ix);
                                self.bullets.clear();
                                self.bullets.push(ix);

                                self.state = State::Bullet;
                            }
                        }
                    }
                }
                State::Header => {
                    if false {
                    } else if self.handle_newline(token) {
                    } else if self.handle_backtick(token) {
                    } else if self.handle_dollar(token) {
                    } else {
                        let header = self.header();
                        header.parts.push(Part::new(&token.range, tree::Kind::Meta));
                    }
                }
                State::Bullet => {
                    if false {
                    } else if self.handle_newline(token) {
                    } else if self.handle_backtick(token) {
                    } else if self.handle_dollar(token) {
                    } else {
                        let bullet = self.bullet();
                        bullet.parts.push(Part::new(&token.range, tree::Kind::Meta));
                    }
                }
                State::Code => {
                    if false {
                    } else if self.handle_newline(token) {
                    } else {
                        let bullet = self.bullet();
                        bullet.parts.push(Part::new(&token.range, tree::Kind::Data));
                        // &improv: clean this up and handle multi-ticks as well
                        if token.kind == lex::Kind::Backtick {
                            self.state = self.prev_state.clone();
                        }
                    }
                }
                State::CodeBlock => {
                    let node = &mut self.nodes[self.codeblock.unwrap()];
                    node.parts.push(Part::new(&token.range, tree::Kind::Data));

                    if token.kind == lex::Kind::Backtick && token.range.len() == 3 {
                        self.codeblock = None;
                        self.state = State::Idle;
                    }
                }
                State::Formula => {
                    if false {
                    } else if self.handle_newline(token) {
                    } else {
                        let bullet = self.bullet();
                        bullet.parts.push(Part::new(&token.range, tree::Kind::Data));
                        // &improv: clean this up and handle multi-dollar as well
                        if token.kind == lex::Kind::Dollar {
                            self.state = self.prev_state.clone();
                        }
                    }
                }
                State::FormulaBlock => {
                    let node = &mut self.nodes[self.formulablock.unwrap()];
                    node.parts.push(Part::new(&token.range, tree::Kind::Data));

                    if token.kind == lex::Kind::Dollar && token.range.len() == 2 {
                        self.formulablock = None;
                        self.state = State::Idle;
                    }
                }
            }
        }
    }

    fn handle_newline(&mut self, token: &Token) -> bool {
        if token.kind == lex::Kind::Newline {
            self.state = State::Idle;
            true
        } else {
            false
        }
    }

    fn handle_backtick(&mut self, token: &Token) -> bool {
        if token.kind == lex::Kind::Backtick {
            let level = token.range.len();

            if level % 2 == 1 {
                if level == 3 {
                    let node = Node {
                        parts: vec![Part::new(&token.range, tree::Kind::Data)],
                        ..Default::default()
                    };
                    let ix = self.append(node);
                    self.bullet().childs.push(ix);
                    self.bullets.push(ix);
                    self.codeblock = Some(ix);

                    self.prev_state = self.state.clone();
                    self.state = State::CodeBlock;
                } else {
                    let bullet = self.bullet();
                    bullet.parts.push(Part::new(&token.range, tree::Kind::Data));

                    self.prev_state = self.state.clone();
                    self.state = State::Code;
                };

                return true;
            }
        }
        false
    }

    fn handle_dollar(&mut self, token: &Token) -> bool {
        if token.kind == lex::Kind::Dollar {
            let level = token.range.len();

            match level {
                1 => {
                    let bullet = self.bullet();
                    bullet.parts.push(Part::new(&token.range, tree::Kind::Data));

                    self.prev_state = self.state.clone();
                    self.state = State::Formula;

                    true
                }
                2 => {
                    let node = Node {
                        parts: vec![Part::new(&token.range, tree::Kind::Data)],
                        ..Default::default()
                    };
                    let ix = self.append(node);
                    self.bullet().childs.push(ix);
                    self.bullets.push(ix);
                    self.formulablock = Some(ix);

                    self.prev_state = self.state.clone();
                    self.state = State::FormulaBlock;

                    true
                }
                _ => false,
            }
        } else {
            false
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
        for part in &node.parts {
            os.push_str(match part.kind {
                tree::Kind::Meta => "M",
                tree::Kind::Data => "D",
            });
            if let Some(s) = content.get(part.range.clone()) {
                os.push_str(s);
            }
        }
        for child in &node.childs {
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
            // Bullet level 0 is the header()
            self.header()
        } else {
            let ix = self.bullets.last().unwrap();
            &mut self.nodes[*ix]
        }
    }

    fn append(&mut self, node: Node) -> usize {
        let ix = self.nodes.len();
        self.nodes.push(node);
        ix
    }
}

impl Node {
    fn new(line_ix: u64) -> Node {
        Node {
            line_ix,
            ..Default::default()
        }
    }
}

type Range = std::ops::Range<usize>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tree() {
        let scns = [
            ("", "()"),
            ("# Title", "((D#M MTitle))"),
            ("# Title\nLine1\nLine2", "((D#M MTitle(MLine1)(MLine2)))"),
            (
                "# T1\nL1\nL2\n# T2\nL3\nL4",
                "((D#M MT1(ML1)(ML2))(D#M MT2(ML3)(ML4)))",
            ),
            (
                "# T1\n## T2\n## T3\n# T4",
                "((D#M MT1(D##M MT2)(D##M MT3))(D#M MT4))",
            ),
            ("L1\n- L2\n- L3\nL4", "((ML1(D-M ML2)(D-M ML3))(ML4))"),
            ("L1\n- L2\n** L3\nL4", "((ML1(D-M ML2(D**M ML3)))(ML4))"),
            (
                "# T\n```\n## code\n```",
                "((D#M MT(D```D\nD##D DcodeD\nD```)))",
            ),
            (
                "# T\n$$\n- formula\n$$",
                "((D#M MT(D$$D\nD-D DformulaD\nD$$)))",
            ),
            ("abc`code`def", "((MabcD`DcodeD`Mdef))"),
            ("# abc`code`def", "((D#M MabcD`DcodeD`Mdef))"),
            ("abc$formula$def", "((MabcD$DformulaD$Mdef))"),
            ("# abc$formula$def", "((D#M MabcD$DformulaD$Mdef))"),
        ];
        let mut lexer = lex::Lexer::new();

        for (content, exp) in scns {
            lexer.tokenize(content);

            let mut tree = Tree::default();
            tree.init(&lexer.tokens);

            assert_eq!(&tree.print(content), exp);
        }
    }
}
