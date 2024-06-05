use crate::{data, tui, util};

pub struct Line {
    region: tui::Region,
}

impl Line {
    pub fn new(region: tui::Region) -> Line {
        Line { region }
    }

    pub fn draw(
        &mut self,
        term: &mut tui::term::Term,
        line: &data::status::Line,
    ) -> util::Result<()> {
        let mut region = self.region;
        Ok(())
    }
}
