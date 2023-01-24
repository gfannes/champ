use crate::my;
use crate::tui::{self, term};
use crossterm::{
    cursor,
    style::{self, Stylize},
    QueueableCommand,
};

pub struct Text {
    region: tui::Region,
    marked: bool,
}

impl Text {
    pub fn new(region: tui::Region) -> Text {
        Text {
            region,
            marked: false,
        }
    }
    pub fn mark(&mut self) {
        self.marked = true;
    }
    pub fn draw(&mut self, term: &mut term::Term, str: impl Into<String>) -> my::Result<()> {
        term.queue(cursor::MoveTo(
            self.region.col as u16,
            self.region.row as u16,
        ))?;

        let mut str = str.into();

        let mut size = None;
        for (count, (ix, _)) in str.char_indices().enumerate() {
            if count == self.region.width {
                size = Some(ix);
                break;
            }
        }
        if let Some(size) = size {
            str.truncate(size);
        }

        if self.marked {
            term.queue(style::PrintStyledContent(
                str.with(style::Color::Green).on(style::Color::DarkGrey),
            ))?;
        } else {
            term.queue(style::Print(str))?;
        }

        Ok(())
    }
}
