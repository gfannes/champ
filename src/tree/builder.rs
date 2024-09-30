use crate::{amp, fs, lex, path, tree, tree::md, tree::src, util};
use std::collections;

type Forest = tree::Forest;
type Tree = tree::Tree;
type Format = tree::Format;
type Node = tree::Node;
type Kind = tree::Kind;
type Part = tree::Part;
type Range = std::ops::Range<usize>;

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

        forest.each_node_mut(|node, content, format| {
            let m = match format {
                Format::Markdown => Some(amp::Match::Everywhere),
                Format::SourceCode { comment: _ } => Some(amp::Match::OnlyStart),
                _ => None,
            };

            if let Some(m) = m {
                for part in &node.parts {
                    if part.kind == tree::Kind::Meta {
                        if let Some(part_content) = content.get(part.range.clone()) {
                            self.amp_parser.parse(part_content, &m);
                            for stmt in &self.amp_parser.stmts {
                                if let amp::Kind::Amp(amp) = &stmt.kind {
                                    node.org.push(amp.clone());
                                }
                            }
                        } else {
                            eprintln!(
                                "Failed to get part_content for {:?} from {}",
                                &part.range,
                                content.len()
                            );
                        }
                    }
                }
            }

            node.ctx = node.org.clone();
            node.agg = node.org.clone();
        });

        forest.each_tree_mut(|tree| {
            tree.root_to_leaf(|src, dst| {
                for amp in &src.org {
                    // We only push data when there is nothing with the same key
                    if dst.ctx.iter().all(|a| a.kv.key != amp.kv.key) {
                        dst.ctx.push(amp.clone());
                    }
                }
            });
            tree.leaf_to_root(|src, dst| {
                for md in &dst.agg {
                    // We collect everything that is different
                    if src.agg.iter().all(|m| m != md) {
                        src.agg.push(md.clone());
                    }
                }
            });
        });

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
        tree.filename = Some(path.into());

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

                    // &improv: combine parts of same kind
                    node.parts = md_node.parts.clone();

                    for child_ix in &md_node.childs {
                        node.childs.push(*child_ix);
                    }
                }
            }
            Format::SourceCode { comment } => {
                if !self.src_trees.contains_key(comment) {
                    match src::Tree::new(comment) {
                        Err(err) => {
                            eprintln!("Could not create src.Tree from '{}': {}", comment, err)
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
                    eprintln!("Could not find src_tree for {}", comment);
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
        let tree_ix = match parent.fs_path()? {
            path::FsPath::Folder(folder) => {
                let mut tree = tree::Tree::folder(&folder);
                for child in fs_forest.list(parent)? {
                    if let Some(tree_ix) =
                        self.add_to_forest_recursive_(&child, level + 1, fs_forest, forest)?
                    {
                        tree.root().links.push(tree_ix);
                    }
                }
                Some(forest.add(tree, level)?)
            }
            path::FsPath::File(fp) => match self.create_tree_from_path(&fp) {
                Err(err) => {
                    eprintln!(
                        "Could not create tree.Tree from '{}': {}",
                        fp.display(),
                        err
                    );
                    None
                }
                Ok(tree) => Some(forest.add(tree, level)?),
            },
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
