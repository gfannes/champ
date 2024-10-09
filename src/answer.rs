use std::path;

#[derive(Default)]
pub struct Answer {
    locations: Vec<Location>,
}

pub struct Location {
    pub filename: path::PathBuf,
    pub line_nr: u64,
    pub content: String,
    pub ctx: String,
}

pub struct Meta {
    pub is_first: bool,
}

impl Answer {
    pub fn new() -> Answer {
        Answer::default()
    }

    pub fn add(&mut self, location: Location) {
        self.locations.push(location);
    }

    pub fn show(&self) {
        let mut ctx_width = 0;
        self.each_location(|location, _meta| {
            ctx_width = std::cmp::max(ctx_width, location.ctx.len());
        });

        self.each_location(|location, meta| {
            if meta.is_first {
                println!("{}", location.filename.display());
            }
            println!(
                "  {:ctx_width$}\t{}\t{}",
                &location.ctx, location.line_nr, &location.content
            );
        })
    }

    pub fn each_location(&self, mut cb: impl FnMut(&Location, &Meta)) {
        let mut filename = path::PathBuf::new();
        for location in &self.locations {
            let is_first = if location.filename != filename {
                filename = location.filename.clone();
                true
            } else {
                false
            };

            cb(location, &Meta { is_first });
        }
    }
}

impl Location {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_api() {}
}
