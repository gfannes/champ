// &a1 &todo: MD here should apply to the whole Tree

use crate::{amp, fail, fs, lex, path, tree, tree::md, tree::src, util};
use std::collections;
use tracing::{error, info, span, trace, warn, Level};

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
    amp_parser: amp::parse::Parser,
}
impl Builder {
    pub fn new() -> Builder {
        Builder {
            lexer: lex::Lexer::new(),
            md_tree: md::Tree::new(),
            src_trees: Default::default(),
            amp_parser: amp::parse::Parser::new(),
        }
    }

    pub fn create_forest_from(&mut self, fs_forest: &mut fs::Forest) -> util::Result<Forest> {
        let mut forest = tree::Forest::new();
        self.add_to_forest_recursive_(&path::Path::root(), 0, fs_forest, &mut forest)?;

        self.init_org_def(&mut forest)?;
        self.join_defs(&mut forest)?;
        self.resolve_org(&mut forest)?;
        self.init_ctx(&mut forest)?;

        Ok(forest)
    }

    // Inits node.def and node.org from
    // - Node metadata
    // - Metadata files (_.amp)
    // Does not join node.def or resolve node.org
    fn init_org_def(&mut self, forest: &mut Forest) -> util::Result<()> {
        let span = span!(Level::TRACE, "init_org_def");
        let _g = span.enter();

        // Parse Meta Node Parts and route them to Node.def or Node.org, depending on being a definition or not
        forest.each_node_mut(|node, content, format, filename| {
            trace!("{}:{}", filename.display(), node.line_ix.unwrap_or(0) + 1,);

            let m = match format {
                Format::Markdown => Some(amp::parse::Match::Everywhere),
                Format::SourceCode { comment: _ } => Some(amp::parse::Match::OnlyStart),
                _ => None,
            };

            if let Some(m) = m {
                for part in &node.parts {
                    if part.kind == tree::Kind::Meta {
                        let mut cb_push_kv = || -> util::Result<()> {
                            let part_content = content
                                .get(part.range.clone())
                                .ok_or_else(|| util::Error::create("Failed to get part content"))?;

                            self.amp_parser.parse(part_content, &m)?;

                            for stmt in &self.amp_parser.stmts {
                                use amp::parse::*;
                                if let Kind::Amp(path) = &stmt.kind {
                                    if path.is_definition {
                                        if node.def.is_some() {
                                            fail!(
                                                "Found double definition in '{}'",
                                                filename.display()
                                            );
                                        }
                                        node.def = Some(path.clone());
                                    } else {
                                        node.org.insert(path.clone());
                                    }
                                }
                            }

                            Ok(())
                        };

                        if let Err(err) = cb_push_kv() {
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

            Ok(())
        })?;

        // Populate Tree.root().org with info from
        // - _.amp for Folders
        // - tree.filename for Files &todo
        for ix in 0..forest.trees.len() {
            let mut md_paths = None;
            let mut md_def: Option<amp::Path> = None;

            {
                let tree = &forest.trees[ix];

                // For a Folder, the Files are indicated by Tree.root().links
                for ix in &tree.root().links {
                    if let Some(md_tree) = forest.trees.get(*ix) {
                        if md_tree
                            .filename
                            .file_name()
                            .and_then(|file_name| Some(file_name.to_string_lossy() == "_.amp"))
                            .unwrap_or(false)
                        {
                            info!("Found Tree metadata for '{}'", tree.filename.display());
                            let mut paths = amp::Paths::new();
                            for ix in 0..md_tree.nodes.len() {
                                let node = &md_tree.nodes[ix];
                                paths.merge(&node.org)?;
                                if let Some(def) = &node.def {
                                    if md_def.is_some() {
                                        fail!(
                                            "A metadata tree can only contain a single def in '{}'",
                                            tree.filename.display()
                                        );
                                    }
                                    if !def.is_absolute {
                                        // &improv: Do we want to relax this? &d0
                                        fail!("A metadata tree can only contain an absolute def in '{}'", tree.filename.display());
                                    }
                                    md_def = Some(def.clone());
                                }
                            }
                            md_paths = Some(paths);
                        }
                    }
                }
            }

            if let Some(md_paths) = md_paths {
                forest.trees[ix].root_mut().org = md_paths;
            }
            forest.trees[ix].root_mut().def = md_def;
        }

        Ok(())
    }

    fn join_defs(&mut self, forest: &mut Forest) -> util::Result<()> {
        let span = span!(Level::TRACE, "join_defs");
        let _g = span.enter();

        // Join defs
        forest.each_tree_mut(|tree| {
            tree.root_to_leaf(|src, dst| {
                if let Some(dst_def) = &mut dst.def {
                    if let Some(src_def) = &src.def {
                        if !src_def.is_absolute {
                            fail!("Source def should be absolute");
                        }
                        if !dst_def.is_absolute {
                            dst.def = Some(src_def.join(dst_def));
                        }
                    }
                } else {
                    dst.def = src.def.clone();
                }
                Ok(())
            })
        })?;

        // Interpret special Tags for defs: ~status, ~priority, ~date and ~duration
        forest.each_node_mut(
            |node: &mut Node, _content: &str, _format: &Format, _filename: &std::path::PathBuf| {
                if let Some(def) = node.def.as_mut() {
                    for part in &mut def.parts {
                        if let amp::Part::Tag(tag) = part {
                            match tag.text.as_str() {
                                "~status" => {
                                    std::mem::swap(part, &mut amp::Part::Status(amp::Status::new()))
                                }
                                "~priority" => {
                                    std::mem::swap(part, &mut amp::Part::Prio(amp::Prio::new(0, 0)))
                                }
                                "~date" => std::mem::swap(
                                    part,
                                    &mut amp::Part::Date(amp::Date::new(0, 0, 0)),
                                ),
                                "~duration" => std::mem::swap(
                                    part,
                                    &mut amp::Part::Duration(amp::Duration::new(0, 0, 0, 0)),
                                ),
                                _ => {}
                            }
                        }
                    }
                }
                Ok(())
            },
        )?;

        Ok(())
    }

    fn resolve_org(&mut self, forest: &mut Forest) -> util::Result<()> {
        let span = span!(Level::INFO, "resolve_org");
        let _g = span.enter();

        // Collect all defined Keys
        let mut defs = amp::Paths::new();
        forest.each_node(|_tree, node| {
            if let Some(def) = &node.def {
                defs.insert(def.clone());
            }
            Ok(())
        })?;

        forest.each_node_mut(
            |node: &mut Node, _content: &str, _format: &Format, filename: &std::path::PathBuf| {
                if !node.org.is_empty() {
                    let mut abs_paths = amp::Paths::new();

                    for path in &node.org.data {
                        // We always resolve to make sure consistent Paths are used with the correct exclusive flag
                        if let Some(mut abs_path) = defs.resolve(path) {
                            info!(
                                "Resolved {} into {} for {}",
                                path,
                                &abs_path,
                                filename.display()
                            );
                            if abs_paths.has_variant(&abs_path) {
                                fail!("Found variant for '{}' in '{}'", &abs_path, &abs_paths);
                            } else {
                                abs_path.is_definition = false;
                                abs_paths.insert(abs_path);
                            }
                        } else {
                            warn!("Could not resolve {} for '{}'", path, filename.display());
                        }
                    }

                    std::mem::swap(&mut node.org, &mut abs_paths);
                }
                Ok(())
            },
        )?;

        forest.defs = defs;

        Ok(())
    }

    fn init_ctx(&mut self, forest: &mut Forest) -> util::Result<()> {
        let span = span!(Level::TRACE, "init_ctx");
        let _g = span.enter();

        // Setup Tree.root().ctx from Tree.root().org
        forest.each_tree_mut(|tree| {
            tree.root_mut().ctx = tree.root().org.clone();
            Ok(())
        })?;

        // Distribute Tree.root().ctx to all its links
        // We iterate over the Trees in reverse because child Trees come before a parent Tree
        for ix in (0..forest.trees.len()).rev() {
            if !forest.trees[ix].root().ctx.data.is_empty() {
                if !forest.trees[ix].root().links.is_empty() {
                    let src_ctx = forest.trees[ix].root().ctx.clone();
                    let links = forest.trees[ix].root().links.clone();

                    for ix in links {
                        if let Some(dst_tree) = forest.trees.get_mut(ix) {
                            let filename = dst_tree.filename.clone();
                            let dst_ctx = &mut dst_tree.root_mut().ctx;
                            for src in &src_ctx.data {
                                if dst_ctx.has_variant(src) {
                                    info!("Found variant for {src} in root ctx of '{}': not inserting", filename.display());
                                } else {
                                    dst_ctx.insert(src.clone());
                                }
                            }
                        }
                    }
                }
            }
        }

        // Distribute the ctx within each Tree
        forest.each_tree_mut(|tree| {
            let filename = tree.filename.clone();
            tree.root_to_leaf(|src, dst| {
                dst.ctx = dst.org.clone();
                for src in &src.ctx.data {
                    if dst.ctx.has_variant(src) {
                        info!(
                            "Found variant for {src} in ctx of '{}': not inserting",
                            filename.display()
                        );
                    } else {
                        dst.ctx.insert(src.clone());
                    }
                }
                Ok(())
            })
        })?;

        Ok(())
    }

    pub fn create_tree_from_path(&mut self, path: &std::path::Path) -> util::Result<Tree> {
        let content = std::fs::read_to_string(path)?;

        let format = path
            .extension()
            .and_then(|ext| {
                let format = match &ext.to_string_lossy() as &str {
                    // &todo: Treat `.amp` as its own file format
                    "md" | "amp" => Format::Markdown,
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
        forest: &mut Forest,
    ) -> util::Result<Option<usize>> {
        let span = span!(Level::TRACE, "add_to_forest_recursive_");
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
