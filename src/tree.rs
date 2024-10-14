pub mod builder;
pub mod md;
pub mod src;

use crate::{amp, fail, rnd, rubr::naft, util};
use std::{collections, path};

// Represents a subset of the filesystem, corresponding with a ignore.Tree
// &next: use ignore.Tree to iterate and populate a tree.Forest
// &next: interconnect Forest and compute Node.reachables
// &next: distribute attributes from root to leaf
// &next: aggregate data from leat to root
#[derive(Default, Debug)]
pub struct Forest {
    files: collections::BTreeMap<path::PathBuf, usize>,
    pub trees: Vec<Tree>,
    roots: Vec<usize>,
    names: Vec<String>,
    pub defs: amp::Paths,
}

// Represents a single file or folder
// &next: create default root always
#[derive(Default, Debug)]
pub struct Tree {
    pub ix: usize,
    pub root_ix: usize,
    pub nodes: Vec<Node>,
    pub filename: path::PathBuf,
    pub format: Format,
    pub content: String,
    // &todo: use root() to store this data instead
    pub org: amp::Paths,
    pub ctx: amp::Paths,
    state: State,
}

// &next: provide amp items
#[derive(Default, Debug)]
pub struct Node {
    pub parts: Vec<Part>,
    pub line_ix: Option<u64>,
    pub tree_ix: usize,
    childs: Vec<usize>,     // Ancestral links to Nodes within the same Tree
    pub links: Vec<usize>,  // Direct links to other Trees
    reachables: Vec<usize>, // All other Trees that are recursively reachable

    pub def: Option<amp::Path>,
    pub org: amp::Paths,
    pub ctx: amp::Paths,
}

#[derive(Debug, Clone)]
pub struct Part {
    pub range: Range,
    pub kind: Kind,
}

#[derive(PartialEq, Eq, Debug, Clone)]
pub enum Kind {
    Meta, // Meta parts are searched for AMP info
    Data,
}

#[derive(Debug, Default, Clone)]
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

#[derive(Debug)]
enum State {
    None,
    OrgNode,
    OrgTree,
    CtxTree,
    CtxNode,
}
impl Default for State {
    fn default() -> State {
        State::None
    }
}
impl std::fmt::Display for State {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            State::None => "None",
            State::OrgNode => "OrgNode",
            State::OrgTree => "OrgTree",
            State::CtxTree => "CtxTree",
            State::CtxNode => "CtxNode",
        };
        write!(f, "{s}")?;
        Ok(())
    }
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

        if self.files.contains_key(&tree.filename) {
            fail!("Forest already contains '{}'", tree.filename.display());
        }
        self.files.insert(tree.filename.clone(), ix);

        tree.ix = self.trees.len();
        for node in &mut tree.nodes {
            node.tree_ix = tree.ix;
        }
        self.trees.push(tree);

        Ok(ix)
    }

    pub fn each_node(
        &self,
        mut cb: impl FnMut(&Tree, &Node) -> util::Result<()>,
    ) -> util::Result<()> {
        for tree in &self.trees {
            tree.each_node(&mut cb)?;
        }
        Ok(())
    }

    pub fn each_node_mut(
        &mut self,
        mut cb: impl FnMut(&mut Node, &str, &Format, &path::PathBuf) -> util::Result<()>,
    ) -> util::Result<()> {
        for tree in &mut self.trees {
            tree.each_node_mut(&mut cb)?;
        }
        Ok(())
    }

    pub fn each_tree_mut(
        &mut self,
        mut cb: impl FnMut(&mut Tree) -> util::Result<()>,
    ) -> util::Result<()> {
        for tree in &mut self.trees {
            cb(tree)?;
        }
        Ok(())
    }

    pub fn dfs(&self, mut cb: impl FnMut(&Tree, &Node) -> util::Result<()>) -> util::Result<()> {
        for &root_ix in &self.roots {
            let root = &self.trees[root_ix];
            self.dfs_(root, &mut cb)?;
        }
        Ok(())
    }
    fn dfs_(
        &self,
        tree: &Tree,
        cb: &mut impl FnMut(&Tree, &Node) -> util::Result<()>,
    ) -> util::Result<()> {
        for node in &tree.nodes {
            cb(tree, node);
            for &tree_ix in &node.links {
                let tree = &self.trees[tree_ix];
                self.dfs_(tree, cb)?;
            }
        }
        Ok(())
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

            let start = tree.content.len();
            tree.content.push_str(&format!("{}", path.display()));
            let end = tree.content.len();

            root.parts.push(Part::new(&(start..end), Kind::Data));
        }
        tree.filename = path.into();
        tree.format = Format::Folder;
        tree
    }

    pub fn each_node(
        &self,
        cb: &mut impl FnMut(&Tree, &Node) -> util::Result<()>,
    ) -> util::Result<()> {
        match self.format {
            Format::Folder => {}
            _ => {
                let mut iter = self.nodes.iter();
                if let Format::SourceCode { comment: _ } = self.format {
                    // First line is the root that does not correspond with actual file content
                    iter.next();
                }
                for node in iter {
                    cb(self, node)?;
                }
            }
        }
        Ok(())
    }

    pub fn each_node_mut(
        &mut self,
        cb: &mut impl FnMut(&mut Node, &str, &Format, &path::PathBuf) -> util::Result<()>,
    ) -> util::Result<()> {
        for node in &mut self.nodes {
            cb(node, &self.content, &self.format, &self.filename)?;
        }

        Ok(())
    }

    pub fn root(&self) -> &Node {
        &self.nodes[self.root_ix]
    }
    pub fn root_mut(&mut self) -> &mut Node {
        &mut self.nodes[self.root_ix]
    }

    pub fn root_to_leaf(
        &mut self,
        mut cb: impl FnMut(&Node, &mut Node) -> util::Result<()>,
    ) -> util::Result<()> {
        let (_, tail) = self.nodes.split_at_mut(self.root_ix);
        Self::root_to_leaf_(self.root_ix, tail, &mut cb)?;
        Ok(())
    }
    fn root_to_leaf_(
        src_ix: usize,
        src_rest: &mut [Node],
        cb: &mut impl FnMut(&Node, &mut Node) -> util::Result<()>,
    ) -> util::Result<()> {
        // We assume that child links only have higher indices
        if let Some((src, rest)) = src_rest.split_first_mut() {
            for &dst_ix in &src.childs {
                let diff = dst_ix - src_ix - 1;
                let (_, tail) = rest.split_at_mut(diff);
                cb(src, &mut tail[0]);
                Self::root_to_leaf_(dst_ix, tail, cb)?;
            }
        }
        Ok(())
    }

    pub fn leaf_to_root(&mut self, mut cb: impl FnMut(&mut Node, &mut Node)) {
        let (_, tail) = self.nodes.split_at_mut(self.root_ix);
        Self::leaf_to_root_(self.root_ix, tail, &mut cb);
    }
    fn leaf_to_root_(
        src_ix: usize,
        src_rest: &mut [Node],
        cb: &mut impl FnMut(&mut Node, &mut Node),
    ) {
        // We assume that child links only have higher indices
        if let Some((src, rest)) = src_rest.split_first_mut() {
            let childs = src.childs.clone();
            for dst_ix in childs {
                let diff = dst_ix - src_ix - 1;
                let (_, tail) = rest.split_at_mut(diff);
                Self::leaf_to_root_(dst_ix, tail, cb);
                cb(src, &mut tail[0]);
            }
        }
    }

    pub fn print(&self) {
        match self.format {
            Format::Folder => {}
            _ => {
                println!("  Tree {:?} {}", self.format, self.filename.display());
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
impl naft::ToNaft for Tree {
    fn to_naft(&self, p: &naft::Node) -> util::Result<()> {
        let n = p.node("Tree")?;
        n.attr("ix", &self.ix)?;
        n.attr("filename", &self.filename.display())?;
        n.attr("state", &self.state)?;
        self.org.to_naft(&n.name("org"));
        self.ctx.to_naft(&n.name("ctx"));
        for ix in 0..self.nodes.len() {
            let node = &self.nodes[ix];
            node.to_naft(&n);
        }
        Ok(())
    }
}

pub type Range = std::ops::Range<usize>;

#[derive(Debug)]
pub enum Aggregate {}

impl Part {
    fn new(range: &Range, kind: Kind) -> Part {
        Part {
            range: range.clone(),
            kind,
        }
    }
}

impl Node {
    pub fn print(&self, content: &str, _format: &Format) {
        if let Some(line_ix) = self.line_ix {
            print!("{:<5}", line_ix + 1);
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

impl naft::ToNaft for Node {
    fn to_naft(&self, p: &naft::Node) -> util::Result<()> {
        let n = p.node("Node")?;
        n.attr("line_nr", &(self.line_ix.unwrap_or(0) + 1))?;
        if let Some(def) = &self.def {
            n.attr("def", def)?;
        }
        self.org.to_naft(&n.name("org"));
        self.ctx.to_naft(&n.name("ctx"));
        Ok(())
    }
}
