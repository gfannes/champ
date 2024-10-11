use crate::{amp, fail, fs, lex, path, rnd, tree, tree::md, tree::src, util};
use std::collections;
use tracing::{error, span, trace, warn, Level};

type Forest = tree::Forest;
type Tree = tree::Tree;
type Format = tree::Format;
type Node = tree::Node;
type Kind = tree::Kind;
type Part = tree::Part;

pub struct Builder {
    lexer: lex::Lexer,
    md_tree: md::Tree,
    src_trees: collections::BTreeMap<String, src::Tree>,
    amp_parser: amp::Parser,
}
impl Builder {
    pub fn new() -> Builder {
        Builder {
            lexer: lex::Lexer::new(),
            md_tree: md::Tree::new(),
            src_trees: Default::default(),
            amp_parser: amp::Parser::new(),
        }
    }

    pub fn create_forest_from(&mut self, fs_forest: &mut fs::Forest) -> util::Result<Forest> {
        let mut forest = tree::Forest::new();
        self.add_to_forest_recursive_(&path::Path::root(), 0, fs_forest, &mut forest)?;

        forest.each_node_mut(|node, content, format, filename| {
            let span = span!(Level::TRACE, "parse");
            let _g = span.enter();
            trace!("{}:{}", filename.display(), node.line_ix.unwrap_or(0) + 1,);

            let m = match format {
                Format::Markdown => Some(amp::Match::Everywhere),
                Format::SourceCode { comment: _ } => Some(amp::Match::OnlyStart),
                _ => None,
            };

            if let Some(m) = m {
                for part in &node.parts {
                    if part.kind == tree::Kind::Meta {
                        let mut push_kv_lmbd = || -> util::Result<()> {
                            let part_content = content
                                .get(part.range.clone())
                                .ok_or_else(|| util::Error::create("Failed to get part content"))?;

                            self.amp_parser.parse(part_content, &m);

                            for stmt in &self.amp_parser.stmts {
                                use amp::*;
                                if let Kind::Amp(kv) = &stmt.kind {
                                    node.org.insert(kv.to_owned());

                                    // &todo: Rework Kind::Amp to contain (String, Option<String>)
                                    node.kvs.push((
                                        kv.key.clone(),
                                        match &kv.value {
                                            value::Value::None => None,
                                            _ => Some(kv.value.to_string()),
                                        },
                                    ));
                                    if rnd::Kind::from(kv.key.as_str()) == rnd::Kind::Absolute {
                                        node.path = Some(rnd::Key::new(kv.key.as_str()));
                                    }
                                }
                            }

                            Ok(())
                        };
                        if let Err(err) = push_kv_lmbd() {
                            error!(
                                "Failed to process KV for '{}:{}': {}",
                                filename.display(),
                                // &todo: replace with function
                                node.line_ix.unwrap_or(0) + 1,
                                &err
                            );
                        }
                    }
                }
            }

            node.ctx = node.org.clone();
            node.agg = node.org.clone();

            Ok(())
        })?;

        forest.each_tree_mut(|tree| {
            // Indicate each Tree is in State::OrgNode
            // - node.org is init
            tree.state = tree::State::OrgNode;
            Ok(())
        })?;

        // Populate Tree.org with info from
        // - _amp.md for Folders
        // - tree.filename for Files
        {
            let span = span!(Level::TRACE, "OrgTree");
            let _g = span.enter();
            for tree_ix in 0..forest.trees.len() {
                {
                    let mut kvs_opt = None;

                    {
                        let tree = &forest.trees[tree_ix];
                        // For a Folder, the Files are indicated by the links on the root Node
                        for link_ix in &tree.root().links {
                            if let Some(link) = forest.trees.get(*link_ix) {
                                if link
                                    .filename
                                    .file_name()
                                    .and_then(|file_name| {
                                        Some(file_name.to_string_lossy() == "_amp.md")
                                    })
                                    .unwrap_or(false)
                                {
                                    trace!("Found Tree metadata for '{}'", tree.filename.display());
                                    let mut kvs = amp::KVSet::new();
                                    for node_ix in 0..link.nodes.len() {
                                        let node = &link.nodes[node_ix];
                                        kvs.merge(&node.org)?;
                                    }
                                    kvs_opt = Some(kvs);
                                }
                            }
                        }
                    }

                    if let Some(kvs) = kvs_opt {
                        forest.trees[tree_ix].org = kvs;
                    }
                }
            }
            // Update state for each Tree
            forest.each_tree_mut(|tree| {
                trace!("{}", tree.filename.display());
                tree.state = tree::State::OrgTree;
                Ok(())
            })?;
        }

        // Push parent:Tree.org into child:Tree.ctx, following parent:Tree.links
        {
            // Copy org to ctx for each Tree
            for tree in &mut forest.trees {
                tree.ctx = tree.org.clone();
            }

            // Note that we iterate backwards: forest construction places childs before parent
            for parent_ix in (0..forest.trees.len()).rev() {
                let parent_tree = &forest.trees[parent_ix];

                if !parent_tree.ctx.is_empty() {
                    let ctx = parent_tree.ctx.clone();
                    let childs = parent_tree.root().links.clone();

                    for child_ix in childs {
                        let dst_tree = forest.trees.get_mut(child_ix).ok_or_else(|| {
                            util::Error::create("Dangling link {link_ix} for for tree {tree_ix}")
                        })?;
                        dst_tree.ctx.merge(&ctx)?;
                    }
                }
            }
        }

        // Copy Tree.ctx into Root.ctx
        // &todo: use Root.ctx directly iso below copy
        forest.each_tree_mut(|tree| {
            tree.root_mut().ctx = tree.ctx.clone();
            Ok(())
        })?;

        // Compute context for each Node, starting with Tree.ctx
        forest.each_tree_mut(|tree| {
            let filename = tree.filename.clone();
            tree.root_to_leaf(|src, dst| {
                dst.ctx = dst.org.clone();
                dst.ctx.merge(&src.ctx)?;

                // Join relative path with their absolute parent path
                if dst.path.is_none() {
                    let mut path = None;
                    for kv in &dst.kvs {
                        let key = rnd::Key::new(kv.0.as_str());
                        if let Some(parent) = &src.path {
                            if let Some(p) = parent.join(&key) {
                                if path.is_some() {
                                    fail!("Only one path is supported")
                                }
                                path = Some(p);
                            }
                        } else if key.kind() == rnd::Kind::Relative {
                            fail!(
                                "Found Relative Key without an Absolute parent in '{}'",
                                filename.display()
                            );
                        }
                    }
                    dst.path = path;
                }
                Ok(())
            })?;
            Ok(())
        })?;

        // // Aggregate data over the Forest
        // forest.each_tree_mut(|tree| {
        //     tree.leaf_to_root(|src, dst| {
        //         for md in &dst.agg {
        //             // We collect everything that is different
        //             if src.agg.iter().all(|m| m != md) {
        //                 src.agg.push(md.clone());
        //             }
        //         }
        //     });
        // });

        Ok(forest)
    }

    pub fn create_tree_from_path(&mut self, path: &std::path::Path) -> util::Result<Tree> {
        let content = std::fs::read_to_string(path)?;

        let format = path
            .extension()
            .and_then(|ext| {
                let format = match &ext.to_string_lossy() as &str {
                    "md" => Format::Markdown,
                    "mm" => Format::MindMap,
                    "rb" | "py" | "sh" => Format::SourceCode { comment: "#" },
                    "h" | "c" | "hpp" | "cpp" | "rs" | "chai" => {
                        Format::SourceCode { comment: "//" }
                    }
                    _ => Format::Unknown,
                };
                Some(format)
            })
            .unwrap_or(Format::Unknown);

        let mut tree = self.create_tree_from_str(&content, format);
        tree.filename = path.into();

        Ok(tree)
    }

    // Creates a flat tree with lines split on '\n'
    // &next: parse content into meronomy, taking Format into account
    // &next: strip whitespace at the end of `main`
    // &todo: make this fail when the parsing Tree cannot be created
    pub fn create_tree_from_str(&mut self, content: &str, format: Format) -> Tree {
        let mut tree = Tree::new();
        tree.content = content.into();
        tree.format = format;

        self.lexer.tokenize(content);

        match tree.format {
            Format::MindMap => todo!("Implement XML-MM parsing"),
            Format::Markdown => {
                self.md_tree.init(&self.lexer.tokens);

                tree.nodes
                    .resize_with(self.md_tree.nodes.len(), || Node::default());

                for (ix, md_node) in self.md_tree.nodes.iter().enumerate() {
                    let node = &mut tree.nodes[ix];
                    node.line_ix = Some(md_node.line_ix);

                    // Combine parts of same kind to ensure amp.Parser can see all metadata at once
                    for md_part in &md_node.parts {
                        if let Some(prev_part) = node.parts.last_mut() {
                            if md_part.kind == prev_part.kind {
                                prev_part.range.end = md_part.range.end;
                                continue;
                            }
                        }
                        node.parts.push(md_part.clone());
                    }

                    for child_ix in &md_node.childs {
                        node.childs.push(*child_ix);
                    }
                }
            }
            Format::SourceCode { comment } => {
                if !self.src_trees.contains_key(comment) {
                    match src::Tree::new(comment) {
                        Err(err) => {
                            error!("Could not create src.Tree from '{}': {}", comment, err)
                        }
                        Ok(src_tree) => {
                            self.src_trees.insert(comment.to_owned(), src_tree);
                        }
                    }
                }

                if let Some(src_tree) = self.src_trees.get_mut(comment) {
                    src_tree.init(&self.lexer.tokens);

                    // Allocate all the Nodes
                    tree.nodes
                        .resize_with(src_tree.nodes.len(), || Node::default());

                    // Copy the data and setup the parental links
                    for (ix, src_node) in src_tree.nodes.iter().enumerate() {
                        let node = &mut tree.nodes[ix];
                        node.line_ix = Some(src_node.line_ix);
                        let kind = if src_node.comment {
                            Kind::Meta
                        } else {
                            Kind::Data
                        };
                        node.parts.push(Part {
                            range: src_node.range.clone(),
                            kind,
                        });

                        for child_ix in &src_node.childs {
                            node.childs.push(*child_ix);
                        }
                    }
                } else {
                    error!("Could not find src_tree for {}", comment);
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

    fn add_to_forest_recursive_(
        &mut self,
        parent: &path::Path,
        level: u64,
        fs_forest: &mut fs::Forest,
        forest: &mut tree::Forest,
    ) -> util::Result<Option<usize>> {
        let span = span!(Level::TRACE, "forest");
        let _g = span.enter();

        let tree_ix = match parent.fs_path()? {
            path::FsPath::Folder(folder) => {
                trace!("Loading folder '{}'", folder.display());
                let mut tree = tree::Tree::folder(&folder);
                for child in fs_forest.list(parent)? {
                    if let Some(tree_ix) =
                        self.add_to_forest_recursive_(&child, level + 1, fs_forest, forest)?
                    {
                        tree.root_mut().links.push(tree_ix);
                    }
                }
                Some(forest.add(tree, level)?)
            }
            path::FsPath::File(fp) => {
                trace!("Loading file '{}'", fp.display());
                match self.create_tree_from_path(&fp) {
                    Err(err) => {
                        warn!(
                            "Could not create tree.Tree from '{}': {}",
                            fp.display(),
                            err
                        );
                        None
                    }
                    Ok(tree) => Some(forest.add(tree, level)?),
                }
            }
        };
        Ok(tree_ix)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_api() -> util::Result<()> {
        let mut forest = tree::Forest::new();
        let mut builder = Builder::new();
        println!("{:?}", &forest);
        {
            let tree = builder.create_tree_from_str("# Title\n- line1\n- line 2", Format::Markdown);
            println!("{:?}", &tree);
            forest.add(tree, 0)?;
        }
        {
            let pwd = std::env::current_dir()?;
            let tree = builder.create_tree_from_path(&pwd.join("test/simple.md"))?;
            println!("{:?}", &tree);
            forest.add(tree, 0)?;
        }

        forest.connect()?;

        Ok(())
    }
}
