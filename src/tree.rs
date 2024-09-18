use crate::util;
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
}

// Represents a single file or folder
#[derive(Default, Debug)]
pub struct Tree {
    root_ix: usize,
    nodes: Vec<Node>,
    filename: Option<path::PathBuf>,
    format: Option<Format>,
    text: String,
}

impl Tree {
    pub fn from_path(path: &path::Path) -> util::Result<Tree> {
        let content = fs::read_to_string(path)?;
        let mut tree = Tree::from_str(&content);
        tree.filename = Some(path.into());
        Ok(tree)
    }

    // Creates a flat tree with lines split on '\n'
    // &next: parse content into meronomy, taking Format into account
    pub fn from_str(content: &str) -> Tree {
        let mut tree: Tree = Default::default();
        tree.text = content.into();
        tree.root_ix = tree.nodes.len();
        tree.nodes.push(Node::default());

        let mut prev_range = Range::default();
        for line in tree.text.split('\n') {
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
}

#[derive(Debug)]
pub enum Format {
    Markdown,
    MindMap,
    SourceCode,
}

pub type Range = std::ops::Range<usize>;

#[derive(Debug)]
pub enum Attribute {}

#[derive(Debug)]
pub enum Aggregate {}

// &next: provide champ items
#[derive(Default, Debug)]
pub struct Node {
    prefix: Range,
    postfix: Range,
    attributes: collections::BTreeMap<usize, Attribute>,
    aggregates: collections::BTreeMap<usize, Aggregate>,
    tree_ix: usize,
    childs: Vec<usize>,     // Ancestral links to Nodes within the same Tree
    links: Vec<usize>,      // Direct links to other Trees
    reachables: Vec<usize>, // All other Trees that are recursively reachable
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
