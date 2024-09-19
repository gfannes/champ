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
        let mut tree = Tree::from_str(&content);
        tree.filename = Some(path.into());
        Ok(tree)
    }

    // Creates a flat tree with lines split on '\n'
    // &next: parse content into meronomy, taking Format into account
    pub fn from_str(content: &str) -> Tree {
        let mut tree = Self::new();
        tree.content = content.into();

        let mut prev_range = Range::default();
        for line in tree.content.split('\n') {
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

    pub fn print(&self) {
        if let Some(filename) = &self.filename {
            println!("  Tree {}", filename.display());
        }
        let n = match self.format {
            Format::Folder => usize::MAX,
            _ => 4,
        };
        for node in self.nodes.iter().take(n) {
            node.print(&self.content, &self.format);
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
    SourceCode,
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
    attributes: collections::BTreeMap<usize, Attribute>,
    aggregates: collections::BTreeMap<usize, Aggregate>,
    pub tree_ix: usize,
    childs: Vec<usize>,     // Ancestral links to Nodes within the same Tree
    links: Vec<usize>,      // Direct links to other Trees
    reachables: Vec<usize>, // All other Trees that are recursively reachable
}

impl Node {
    pub fn print(&self, content: &str, format: &Format) {
        print!("....");
        match content.get(Range {
            start: self.prefix.end,
            end: self.postfix.start,
        }) {
            None => println!("<invalid content>"),
            Some(s) => match format {
                Format::Folder => println!("{}", s),
                _ => {
                    let s: String = s.chars().take(30).collect();
                    println!("{}", s)
                }
            },
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
            let tree = Tree::from_str("# Title\n- line1\n- line 2");
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
