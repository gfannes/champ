use crate::{amp, answer, fail, tree, util};
use tracing::trace;

#[derive(Debug, Default)]
pub struct Query {
    pub needle: Option<amp::KeyValue>,
    pub constraints: Vec<amp::KeyValue>,
}

pub fn search(forest: &tree::Forest, query: &Query) -> util::Result<answer::Answer> {
    let mut answer = answer::Answer::new();

    forest.dfs(|tree, node| {
        let mut is_match = match &query.needle {
            Some(needle) => node.org.has(needle),
            _ => !node.org.is_empty(),
        };
        for constraint in &query.constraints {
            if !node.ctx.has(constraint) {
                is_match = false;
            }
        }

        if is_match {
            let mut prio = amp::value::Prio {
                major: Some(21),
                minor: 0,
            };
            node.ctx.for_each(|k, v| {
                if k == "prio" {
                    match v {
                        amp::value::Value::Prio(p) => prio = p.clone(),
                        _ => fail!("Expected 'prio' to be a value.Prio"),
                    }
                }
                Ok(())
            })?;

            let content = node
                .parts
                .iter()
                .filter_map(|part| tree.content.get(part.range.clone()))
                .collect();
            let ctx = format!("{}", &node.ctx);

            answer.add(answer::Location {
                filename: tree.filename.clone(),
                // &todo: replace with function
                line_nr: node.line_ix.unwrap_or(0) + 1,
                ctx,
                content,
                prio,
            });
        }
        Ok(())
    })?;

    Ok(answer)
}

impl TryFrom<&Vec<String>> for Query {
    type Error = util::ErrorType;
    fn try_from(args: &Vec<String>) -> util::Result<Query> {
        let needle: Option<amp::KeyValue>;
        let mut constraints = Vec::<amp::KeyValue>::new();

        {
            if let Some((needle_str, constraints_str)) = args.split_first() {
                let mut amp_parser = amp::Parser::new();
                match needle_str.as_str() {
                    // &doc: Both an empty argument or '_' will serve as a wildcard
                    "" | "_" => {
                        trace!("Found wildcard '{}' for needle", needle_str);
                        needle = None;
                    }
                    _ => {
                        amp_parser.parse(&format!("&{needle_str}"), &amp::Match::OnlyStart);
                        if let Some(stmt) = amp_parser.stmts.first() {
                            match &stmt.kind {
                                amp::Kind::Amp(kv) => needle = Some(kv.clone()),
                                _ => fail!("Expected to find AMP"),
                            }
                        } else {
                            fail!("Expected to find at least one statement");
                        }
                    }
                }
                for constraint_str in constraints_str {
                    amp_parser.parse(&format!("&{constraint_str}"), &amp::Match::OnlyStart);
                    if let Some(stmt) = amp_parser.stmts.first() {
                        match &stmt.kind {
                            amp::Kind::Amp(kv) => constraints.push(kv.clone()),
                            _ => fail!("Expected to find AMP"),
                        }
                    }
                }
            } else {
                needle = None;
            }
        }
        trace!("needle: {:?}", needle);
        trace!("constraints: {:?}", constraints);

        Ok(Query {
            needle,
            constraints,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_api() {}
}
