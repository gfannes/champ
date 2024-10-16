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

        let mut org_width = 0;
        let mut ctx_width = 0;
        {
            let mut counter = rubr::counter::Counter::new(count);
            self.each_location(|location, _meta| {
                if counter.call() {
                    org_width = std::cmp::max(org_width, location.org.len());
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
                        "  {}\t{:org_width$}\t{:ctx_width$}\t{:>4}: {}",
                        &location.prio,
                        &location.org,
                        &location.ctx,
                        location.line_nr,
                        &location.content
                    )
                    .unwrap();

                    let color;
                    if true {
                        let mut r: u8;
                        let mut g: u8;
                        let mut b: u8;
                        match location.prio.major {
                            0..2 => {
                                r = 255;
                                g = 0;
                                b = 0;
                            }
                            2..4 => {
                                r = 255;
                                g = 127;
                                b = 0;
                            }
                            4..6 => {
                                r = 255;
                                g = 255;
                                b = 0;
                            }
                            6..8 => {
                                r = 0;
                                g = 255;
                                b = 0;
                            }
                            8..10 => {
                                r = 0;
                                g = 0;
                                b = 255;
                            }
                            _ => {
                                r = 255;
                                g = 255;
                                b = 255;
                            }
                        }
                        r = ((r as u32 * 10) / (location.prio.minor + 10)) as u8;
                        g = ((g as u32 * 10) / (location.prio.minor + 10)) as u8;
                        b = ((b as u32 * 10) / (location.prio.minor + 10)) as u8;
                        color = colored::Color::TrueColor { r, g, b };
                    } else {
                        let mut color_str = String::new();
                        match location.prio.minor {
                            0..1 => color_str.push_str("bright "),
                            _ => {}
                        }
                        let s = match location.prio.major {
                            0..2 => "red",
                            2..4 => "orange",
                            4..6 => "yellow",
                            6..8 => "green",
                            8..10 => "blue",
                            _ => "brown",
                        };
                        color_str.push_str(s);
                        color = colored::Color::from(color_str);
                    }

                    let os = os.color(color);
                    println!("{}", &os);
                }
            });
        }
    }
}
