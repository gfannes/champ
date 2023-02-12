use crate::data;
use crate::my;
use crate::tui;
use crate::tui::term;

pub struct Line {
    region: tui::Region,
}

impl Line {
    pub fn new(region: tui::Region) -> Line {
        Line { region }
    }

    pub fn draw(&mut self, term: &mut term::Term, line: &data::status::Line) -> my::Result<()> {
        let mut region = self.region;
        Ok(())
    }
}
