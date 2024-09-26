use crate::lex;

#[derive(Default, Debug)]
pub struct Node {
    pub range: Range,
    pub verbatim: bool,
    pub childs: Vec<usize>,
}

#[derive(Default, Debug)]
pub struct Tree {
    pub nodes: Vec<Node>,
    headers: Vec<usize>,
    bullets: Vec<usize>,
    codeblock: Option<usize>,
    formulablock: Option<usize>,
}

enum State {
    Idle,
    Header,
    Bullet,
    Code,
    CodeBlock,
    Formula,
    FormulaBlock,
}

type Token = lex::Token;
type Kind = lex::Kind;

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

        let mut state = State::Idle;
        for token in tokens {
            let check_newline = |state: &mut State| {
                if token.kind == Kind::Newline {
                    *state = State::Idle;
                    true
                } else {
                    false
                }
            };

            match state {
                State::Idle => {
                    if !check_newline(&mut state) {
                        let mut default = || {
                            let node = Node {
                                range: token.range.clone(),
                                ..Default::default()
                            };
                            let ix = self.append(node);
                            self.header().childs.push(ix);
                            self.bullets.clear();
                            self.bullets.push(ix);

                            state = State::Bullet;
                        };

                        match token.kind {
                            Kind::Hash => {
                                self.bullets.clear();

                                let level = token.range.len();
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

                                state = State::Header;
                            }
                            Kind::Dash | Kind::Star => {
                                let level = token.range.len();
                                assert!(level > 0);
                                // Drop all bullets that are nested deeper
                                while self.bullets.len() > level {
                                    self.bullets.pop();
                                }
                                // Create missing bullets
                                while self.bullets.len() <= level {
                                    let node = Node::default();
                                    let ix = self.append(node);
                                    self.bullet().childs.push(ix);
                                    self.bullets.push(ix);
                                }
                                let bullet = self.bullet();
                                bullet.range = token.range.clone();

                                state = State::Bullet;
                            }
                            Kind::Backtick => {
                                let level = token.range.len();
                                match level {
                                    1 => state = State::Code,
                                    3 => {
                                        let node = Node {
                                            range: token.range.clone(),
                                            verbatim: true,
                                            ..Default::default()
                                        };
                                        let ix = self.append(node);
                                        self.bullet().childs.push(ix);
                                        self.bullets.push(ix);
                                        self.codeblock = Some(ix);

                                        state = State::CodeBlock;
                                    }
                                    _ => default(),
                                }
                            }
                            Kind::Dollar => {
                                let level = token.range.len();
                                match level {
                                    1 => state = State::Formula,
                                    2 => {
                                        let node = Node {
                                            range: token.range.clone(),
                                            verbatim: true,
                                            ..Default::default()
                                        };
                                        let ix = self.append(node);
                                        self.bullet().childs.push(ix);
                                        self.bullets.push(ix);
                                        self.formulablock = Some(ix);

                                        state = State::FormulaBlock;
                                    }
                                    _ => default(),
                                }
                            }
                            _ => {
                                default();
                            }
                        }
                    }
                }
                State::Header => {
                    if !check_newline(&mut state) {
                        let header = self.header();
                        header.range.end = token.range.end;
                    }
                }
                State::Bullet => {
                    if !check_newline(&mut state) {
                        let bullet = self.bullet();
                        bullet.range.end = token.range.end;
                    }
                }
                State::Code => {
                    if !check_newline(&mut state) {
                        let bullet = self.bullet();
                        bullet.range.end = token.range.end;
                    }
                }
                State::CodeBlock => {
                    let node = &mut self.nodes[self.codeblock.unwrap()];
                    node.range.end = token.range.end;

                    if token.kind == Kind::Backtick && token.range.len() == 3 {
                        self.codeblock = None;
                        state = State::Idle;
                    }
                }
                State::Formula => {
                    if !check_newline(&mut state) {
                        let bullet = self.bullet();
                        bullet.range.end = token.range.end;
                    }
                }
                State::FormulaBlock => {
                    let node = &mut self.nodes[self.formulablock.unwrap()];
                    node.range.end = token.range.end;

                    if token.kind == Kind::Dollar && token.range.len() == 2 {
                        self.formulablock = None;
                        state = State::Idle;
                    }
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

type Range = std::ops::Range<usize>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tree() {
        let scns = [
            ("", "()"),
            ("# Title", "((# Title))"),
            ("# Title\nLine1\nLine2", "((# Title(Line1)(Line2)))"),
            (
                "# T1\nL1\nL2\n# T2\nL3\nL4",
                "((# T1(L1)(L2))(# T2(L3)(L4)))",
            ),
            ("# T1\n## T2\n## T3\n# T4", "((# T1(## T2)(## T3))(# T4))"),
            ("L1\n- L2\n- L3\nL4", "((L1(- L2)(- L3))(L4))"),
            ("L1\n- L2\n** L3\nL4", "((L1(- L2(** L3)))(L4))"),
            ("# T\n```\n## code\n```", "((# T(```\n## code\n```)))"),
            ("# T\n$$\n- formula\n$$", "((# T($$\n- formula\n$$)))"),
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
