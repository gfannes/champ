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

        let mut ix = 0;
        if let Some(focus_ix) = list.focus {
            if focus_ix >= self.region.height {
                ix = focus_ix - self.region.height + 1;
            }
        }

        while let Some(line) = region.pop(1, tui::Side::Top) {
            let mut text = tui::Text::new(line);
            if let Some(focus_ix) = list.focus {
                if focus_ix == ix {
                    text.mark();
                }
            }

            if let Some(item) = list.items.get(ix) {
                text.draw(term, item)?;
            } else {
                text.clear(term)?;
            }

            ix += 1;
        }

        Ok(())
    }
}
