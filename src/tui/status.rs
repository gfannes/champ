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
        _term: &mut tui::term::Term,
        _line: &data::status::Line,
    ) -> util::Result<()> {
        let _region = self.region;
        Ok(())
    }
}
