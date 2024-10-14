use crate::{amp, answer, rubr};
use colored::Colorize;
use std::fmt::Write;

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
                        let s = format!("{}", location.filename.display()).blue();
                        println!("{}", s);
                    }
                    // let proj = match &location.proj {
                    //     Some(proj) => proj.to_string(),
                    //     None => "".to_owned(),
                    // };

                    let mut os = String::new();
                    write!(
                        os,
                        "  {}\t{:ctx_width$}\t{:>4}: {}",
                        &location.prio, &location.ctx, location.line_nr, &location.content
                    )
                    .unwrap();
                    let color = match &location.prio {
                        amp::Prio {
                            major: Some(major),
                            minor: _,
                        } => match major {
                            0..2 => "red",
                            2..4 => "orange",
                            4..6 => "yellow",
                            6..8 => "green",
                            8..10 => "blue",
                            _ => "brown",
                        },
                        _ => "grey",
                    };
                    let os = os.color(colored::Color::from(color));
                    println!("{}", &os);
                }
            });
        }
    }
}
