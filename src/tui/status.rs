use crate::{data, tui, util};

pub struct Line {
    region: tui::layout::Region,
}

impl Line {
    pub fn new(region: tui::layout::Region) -> Line {
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
