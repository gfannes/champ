pub mod builder;
pub mod md;
pub mod src;

use crate::{amp, fail, util};
use std::{collections, path};

// Represents a subset of the filesystem, corresponding with a ignore.Tree
// &next: use ignore.Tree to iterate and populate a tree.Forest
// &next: interconnect Forest and compute Node.reachables
// &next: distribute attributes from root to leaf
// &next: aggregate data from leat to root
#[derive(Default, Debug)]
pub struct Forest {
    files: collections::BTreeMap<path::PathBuf, usize>,
    trees: Vec<Tree>,
    roots: Vec<usize>,
    names: Vec<String>,
}

impl Forest {
    pub fn new() -> Forest {
        Default::default()
    }

    pub fn add(&mut self, mut tree: Tree, level: u64) -> util::Result<usize> {
        let ix = self.trees.len();

        if level == 0 {
            self.roots.push(ix);
        }

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

        Ok(ix)
    }

    pub fn each_node(&self, mut cb: impl FnMut(&Tree, &Node) -> ()) {
        for tree in &self.trees {
            tree.each_node(&mut cb);
        }
    }

    pub fn each_node_mut(&mut self, mut cb: impl FnMut(&mut Node, &str) -> ()) {
        for tree in &mut self.trees {
            tree.each_node_mut(&mut cb);
        }
    }

    pub fn dfs(&self, mut cb: impl FnMut(&Tree, &Node) -> ()) {
        for &root_ix in &self.roots {
            println!("root_ix {root_ix}");
            let root = &self.trees[root_ix];
            self.dfs_(root, &mut cb);
        }
    }
    fn dfs_(&self, tree: &Tree, cb: &mut impl FnMut(&Tree, &Node) -> ()) {
        for node in &tree.nodes {
            cb(tree, node);
            for &tree_ix in &node.links {
                let tree = &self.trees[tree_ix];
                self.dfs_(tree, cb);
            }
        }
    }

    pub fn connect(&mut self) -> util::Result<()> {
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
    pub fn folder(path: &path::Path) -> Tree {
        let mut tree = Tree::new();
        {
            let root = &mut tree.nodes[tree.root_ix];

            let mut range = Range::default();
            range.start = tree.content.len();

            tree.content.push_str(&format!("{}", path.display()));
            range.end = tree.content.len();

            root.parts.push(Part::new(range, Kind::Data));
        }
        tree.filename = Some(path.into());
        tree.format = Format::Folder;
        tree
    }

    pub fn each_node(&self, cb: &mut impl FnMut(&Tree, &Node) -> ()) {
        match self.format {
            Format::Folder => {}
            _ => {
                let mut iter = self.nodes.iter();
                if let Format::SourceCode { comment: _ } = self.format {
                    // First line is the root that does not correspond with actual file content
                    iter.next();
                }
                for node in iter {
                    cb(self, node);
                }
            }
        }
    }

    pub fn each_node_mut(&mut self, cb: &mut impl FnMut(&mut Node, &str) -> ()) {
        match self.format {
            Format::Folder => {}
            _ => {
                let content = self.content.to_owned();
                let mut iter = self.nodes.iter_mut();
                if let Format::SourceCode { comment: _ } = self.format {
                    // First line is the root that does not correspond with actual file content
                    iter.next();
                }
                for node in iter {
                    cb(node, &content);
                }
            }
        }
    }

    pub fn root(&mut self) -> &mut Node {
        &mut self.nodes[self.root_ix]
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

#[derive(PartialEq, Eq, Debug)]
pub enum Kind {
    Meta,
    Data,
}
#[derive(Debug)]
pub struct Part {
    pub range: Range,
    pub kind: Kind,
}
impl Part {
    fn new(range: Range, kind: Kind) -> Part {
        Part { range, kind }
    }
}

// &next: provide amp items
#[derive(Default, Debug)]
pub struct Node {
    pub parts: Vec<Part>,
    pub line_nr: Option<u64>,
    pub orig: Vec<amp::Metadata>,
    aggregates: collections::BTreeMap<usize, Aggregate>, // usize points into Forest.names
    pub tree_ix: usize,
    childs: Vec<usize>,     // Ancestral links to Nodes within the same Tree
    pub links: Vec<usize>,  // Direct links to other Trees
    reachables: Vec<usize>, // All other Trees that are recursively reachable
}

impl Node {
    pub fn print(&self, content: &str, format: &Format) {
        if let Some(line_nr) = self.line_nr {
            print!("{:<5}", line_nr);
        } else {
            print!(".....");
        }

        for part in &self.parts {
            if let Some(s) = content.get(part.range.clone()) {
                println!("{}", s);
            }
        }
    }
}
