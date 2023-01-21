use crate::data;
use crate::my;
use crate::tui;
use crate::tui::term;

pub struct List {
    region: tui::Region,
}

impl List {
    pub fn new(region: tui::Region) -> List {
        List { region }
    }
    pub fn draw(&mut self, term: &mut term::Term, list: &data::List) -> my::Result<()> {
        let mut region = self.region;
        for (ix0, item) in list.items.iter().enumerate() {
            if let Some(line) = region.pop(1, tui::Side::Top) {
                let mut text = tui::Text::new(line);
                if let Some(focus_ix) = list.focus {
                    if focus_ix == ix0 {
                        text.mark();
                    }
                }
                text.draw(term, item);
            }
        }
        Ok(())
    }
}
