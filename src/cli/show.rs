use crate::{answer, rubr};

pub enum Display {
    All,
    First(u64),
}

pub trait Show {
    fn show(&self, display: &Display);
}

impl Show for answer::Answer {
    fn show(&self, display: &Display) {
        let count = match display {
            Display::All => None,
            Display::First(n) => Some(*n),
        };

        let mut ctx_width = 0;
        {
            let mut counter = rubr::counter::Counter::new(count);
            self.each_location(|location, _meta| {
                if counter.call() {
                    ctx_width = std::cmp::max(ctx_width, location.ctx.len());
                }
            });
        }

        {
            let mut counter = rubr::counter::Counter::new(count);
            self.each_location(|location, meta| {
                if counter.call() {
                    if meta.is_other_file {
                        println!("{}", location.filename.display());
                    }
                    let proj = match &location.proj {
                        Some(proj) => proj.to_string(),
                        None => "".to_owned(),
                    };
                    println!(
                        "  {}\t{}\t{:ctx_width$}\t{}: {}",
                        &location.prio, proj, &location.ctx, location.line_nr, &location.content
                    );
                }
            });
        }
    }
}
