use crate::{amp, answer, fail, rubr::naft, tree, util};
use tracing::{info, trace};

#[derive(Debug, Default)]
pub struct Query {
    pub needle: Option<amp::Path>,
    pub constraints: Vec<amp::Path>,
}

#[derive(Debug, Clone)]
pub enum From {
    Org,
    Ctx,
}

// `from` determines where `query.needle` is searched.
// `query.constraints` are always searched in `Node.ctx`
pub fn search(forest: &tree::Forest, query: &Query, from: &From) -> util::Result<answer::Answer> {
    let mut answer = answer::Answer::new();

    forest.dfs(|tree, node| {
        let mut is_match;
        {
            let paths = match from {
                From::Org => &node.org,
                From::Ctx => &node.ctx,
            };

            is_match = match &query.needle {
                Some(needle) => paths.matches_with(needle),
                _ => !paths.is_empty(),
            };
        }

        for constraint in &query.constraints {
            if !node.ctx.matches_with(constraint) {
                is_match = false;
            }
        }

        if is_match {
            let content = node
                .parts
                .iter()
                .filter_map(|part| tree.content.get(part.range.clone()))
                .collect();
            let org = node.org.to_string();
            let ctx = node.ctx.to_string();
            // info!("{} org {} ctx {}", tree.filename.display(), &org, &ctx);
            let prio = node
                .ctx
                .data
                .iter()
                .filter_map(|path| path.get_prio().map(Clone::clone))
                .next()
                .unwrap_or_else(|| amp::Prio::new(5, 0));

            answer.add(answer::Location {
                filename: tree.filename.clone(),
                // &todo: replace with function
                line_nr: node.line_ix.unwrap_or(0) + 1,
                org,
                ctx,
                content,
                prio,
            });
        }
        Ok(())
    })?;

    Ok(answer)
}

impl naft::ToNaft for Query {
    fn to_naft(&self, b: &mut naft::Body<'_, '_>) -> std::fmt::Result {
        b.node(&"Node")?;
        if let Some(needle) = &self.needle {
            b.set_ctx("needle");
            needle.to_naft(b)?;
        }
        for constraint in &self.constraints {
            b.set_ctx("constraint");
            constraint.to_naft(b)?;
        }
        Ok(())
    }
}

// Creates a Query from CLI arguments
impl TryFrom<(&Option<String>, &Vec<String>)> for Query {
    type Error = util::ErrorType;

    fn try_from(args: (&Option<String>, &Vec<String>)) -> util::Result<Query> {
        let mut amp_parser = amp::parse::Parser::new();

        let needle: Option<amp::Path>;
        {
            if let Some(needle_str) = args.0 {
                match needle_str.as_str() {
                    // &doc: Both an empty argument or '_' will serve as a wildcard
                    "" | "_" | "~" => {
                        trace!("Found wildcard '{}' for needle", needle_str);
                        needle = None;
                    }
                    _ => {
                        amp_parser
                            .parse(&format!("&{needle_str}"), &amp::parse::Match::OnlyStart)?;
                        if let Some(stmt) = amp_parser.stmts.first() {
                            match &stmt.kind {
                                amp::parse::Kind::Amp(kv) => needle = Some(kv.clone()),
                                _ => fail!("Expected to find AMP"),
                            }
                        } else {
                            fail!("Expected to find at least one statement");
                        }
                    }
                }
            } else {
                needle = None;
            }
        }
        trace!("needle: {:?}", needle);

        let mut constraints = Vec::<amp::Path>::new();
        for constraint_str in args.1 {
            amp_parser.parse(&format!("&{constraint_str}"), &amp::parse::Match::OnlyStart)?;
            if let Some(stmt) = amp_parser.stmts.first() {
                match &stmt.kind {
                    amp::parse::Kind::Amp(kv) => constraints.push(kv.clone()),
                    _ => fail!("Expected to find AMP"),
                }
            }
        }
        trace!("constraints: {:?}", constraints);

        Ok(Query {
            needle,
            constraints,
        })
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_api() {}
}
