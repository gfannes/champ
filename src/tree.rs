use crate::{fail, util};
use std::{collections, fs, path};

// Represents a subset of the filesystem, corresponding with a ignore.Tree
// &next: use ignore.Tree to iterate and populate a tree.Forest
// &next: interconnect Forest and compute Node.reachables
// &next: distribute attributes from root to leaf
// &next: aggregate data from leat to root
#[derive(Default, Debug)]
pub struct Forest {
    files: collections::BTreeMap<path::PathBuf, usize>,
    trees: Vec<Tree>,
    names: Vec<String>,
}

impl Forest {
    pub fn new() -> Forest {
        Default::default()
    }

    pub fn add(&mut self, mut tree: Tree) -> util::Result<()> {
        let ix = self.trees.len();

        if let Some(filename) = &tree.filename {
            if self.files.contains_key(filename) {
                fail!("Forest already contains '{}'", filename.display());
            }
            self.files.insert(filename.clone(), ix);
        }

        tree.ix = self.trees.len();
        for node in &mut tree.nodes {
            node.tree_ix = tree.ix;
        }
        self.trees.push(tree);

        Ok(())
    }

    pub fn each_node(&self, mut cb: impl FnMut(&Tree, &Node) -> ()) {
        for tree in &self.trees {
            tree.each_node(tree, &mut cb);
        }
    }

    pub fn print(&self) {
        println!("Forest with {} trees:", self.trees.len());
        for tree in &self.trees {
            tree.print();
        }
    }
}

// Represents a single file or folder
// &next: create default root always
#[derive(Default, Debug)]
pub struct Tree {
    pub ix: usize,
    pub root_ix: usize,
    pub nodes: Vec<Node>,
    pub filename: Option<path::PathBuf>,
    pub format: Format,
    pub content: String,
}

impl Tree {
    // Create a default root node
    pub fn new() -> Tree {
        Tree {
            root_ix: 0,
            nodes: [Node::default()].into(),
            ..Default::default()
        }
    }

    pub fn from_path(path: &path::Path) -> util::Result<Tree> {
        let content = fs::read_to_string(path)?;

        let format = path
            .extension()
            .and_then(|ext| {
                let format = match &ext.to_string_lossy() as &str {
                    "md" => Format::Markdown,
                    "mm" => Format::MindMap,
                    "rb" | "py" | "sh" => Format::SourceCode { comment: "#" },
                    "bat" => Format::SourceCode { comment: "REM" },
                    "h" | "c" | "hpp" | "cpp" | "rs" | "chai" => {
                        Format::SourceCode { comment: "//" }
                    }
                    _ => Format::Unknown,
                };
                Some(format)
            })
            .unwrap_or(Format::Unknown);

        let mut tree = Tree::from_str(&content, format);
        tree.filename = Some(path.into());

        Ok(tree)
    }

    // Creates a flat tree with lines split on '\n'
    // &next: parse content into meronomy, taking Format into account
    // &next: strip whitespace at the end of `main`
    pub fn from_str(content: &str, format: Format) -> Tree {
        let mut tree = Self::new();
        tree.content = content.into();
        tree.format = format;

        match &tree.format {
            Format::MindMap => todo!("Implement XML-MM parsing"),
            Format::Markdown => {
                let mut prev_range = Range::default();
                let mut line_nr = 0 as u64;
                for line in tree.content.split('\n') {
                    line_nr += 1;

                    let start_ix = prev_range.end;
                    let end_ix = start_ix + line.len();

                    let node = Node {
                        prefix: Range {
                            start: start_ix,
                            end: start_ix,
                        },
                        postfix: Range {
                            start: end_ix,
                            end: end_ix + 1,
                        },
                        line_nr: Some(line_nr),
                        ..Default::default()
                    };
                    let node_ix = tree.nodes.len();
                    tree.nodes.push(node);
                    tree.nodes[tree.root_ix].childs.push(node_ix);

                    prev_range = Range {
                        start: start_ix,
                        end: end_ix + 1,
                    };
                }
            }
            Format::SourceCode { comment } => {
                let mut prev_range = Range::default();
                let mut line_nr = 0 as u64;
                for line in tree.content.split('\n') {
                    line_nr += 1;

                    let start_ix = prev_range.end;
                    let end_ix = start_ix + line.len();

                    if let Some(comment_ix) = line.find(comment) {
                        let node = Node {
                            prefix: Range {
                                start: start_ix,
                                end: start_ix + comment_ix + comment.len(),
                            },
                            postfix: Range {
                                start: end_ix,
                                end: end_ix + 1,
                            },
                            line_nr: Some(line_nr),
                            ..Default::default()
                        };
                        let node_ix = tree.nodes.len();
                        tree.nodes.push(node);
                        tree.nodes[tree.root_ix].childs.push(node_ix);
                    }

                    prev_range = Range {
                        start: start_ix,
                        end: end_ix + 1,
                    };
                }
            }
            _ => {
                if false {
                    todo!("Implement {:?} parsing", &tree.format)
                }
            }
        }
        tree
    }

    pub fn folder(path: &path::Path) -> Tree {
        let mut tree = Tree::new();
        {
            let root = &mut tree.nodes[tree.root_ix];
            root.prefix.start = tree.content.len();
            root.prefix.end = tree.content.len();
            tree.content.push_str(&format!("{}", path.display()));
            root.postfix.start = tree.content.len();
            root.postfix.end = tree.content.len();
        }
        tree.filename = Some(path.into());
        tree.format = Format::Folder;
        tree
    }

    pub fn each_node(&self, tree: &Tree, cb: &mut impl FnMut(&Tree, &Node) -> ()) {
        match self.format {
            Format::Folder => {}
            _ => {
                let mut iter = self.nodes.iter();
                if let Format::SourceCode { comment: _ } = self.format {
                    // First line is the root that does not correspond with actual file content
                    iter.next();
                }
                for node in iter {
                    cb(tree, node);
                }
            }
        }
    }

    pub fn print(&self) {
        match self.format {
            Format::Folder => {}
            _ => {
                if let Some(filename) = &self.filename {
                    println!("  Tree {:?} {}", self.format, filename.display());
                }
                let n = match self.format {
                    Format::Folder => usize::MAX,
                    _ => 4,
                };
                let mut iter = self.nodes.iter();
                if let Format::SourceCode { comment: _ } = self.format {
                    // First line is the root that does not correspond with actual file content
                    iter.next();
                }
                for node in iter.take(n) {
                    node.print(&self.content, &self.format);
                }
            }
        }
    }
}

#[derive(Debug, Default)]
pub enum Format {
    #[default]
    Unknown,
    Folder,
    Markdown,
    MindMap,
    SourceCode {
        comment: &'static str,
    },
}

pub type Range = std::ops::Range<usize>;

#[derive(Debug)]
pub enum Attribute {}

#[derive(Debug)]
pub enum Aggregate {}

// &next: provide amp items
#[derive(Default, Debug)]
pub struct Node {
    pub prefix: Range,
    pub postfix: Range,
    pub line_nr: Option<u64>,
    attributes: collections::BTreeMap<usize, Attribute>,
    aggregates: collections::BTreeMap<usize, Aggregate>,
    pub tree_ix: usize,
    childs: Vec<usize>,     // Ancestral links to Nodes within the same Tree
    links: Vec<usize>,      // Direct links to other Trees
    reachables: Vec<usize>, // All other Trees that are recursively reachable
}

impl Node {
    pub fn get_main<'a>(&self, content: &'a str) -> &'a str {
        match content.get(self.main_range()) {
            None => {
                eprintln!("Encountered invalid content, maybe an UTF-8 issue?");
                ""
            }
            Some(s) => s,
        }
    }

    pub fn print(&self, content: &str, format: &Format) {
        if let Some(line_nr) = self.line_nr {
            print!("{:<5}", line_nr);
        } else {
            print!(".....");
        }

        let main = self.get_main(content);
        match format {
            Format::Folder => println!("{}", main),
            _ => {
                let s: String = main.chars().take(80).collect();
                println!("{}", s)
            }
        }
    }

    fn main_range(&self) -> Range {
        Range {
            start: self.prefix.end,
            end: self.postfix.start,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_api() -> util::Result<()> {
        let mut forest = Forest::new();
        println!("{:?}", &forest);
        {
            let tree = Tree::from_str("# Title\n- line1\n- line 2", Format::Markdown);
            println!("{:?}", &tree);
        }
        {
            let pwd = std::env::current_dir()?;
            let tree = Tree::from_path(&pwd.join("test/simple.md"))?;
            println!("{:?}", &tree);
        }

        Ok(())
    }
}
