use crate::{tui, util};

use crossterm::{
    cursor,
    style::{self, Stylize},
    QueueableCommand,
};
use unicode_width::UnicodeWidthChar;

pub struct Text {
    region: tui::layout::Region,
    marked: bool,
}

impl Text {
    pub fn new(region: tui::layout::Region) -> Text {
        Text {
            region,
            marked: false,
        }
    }
    pub fn mark(&mut self) -> &mut Self {
        self.marked = true;
        self
    }
    pub fn set_mark(&mut self, b: bool) -> &mut Self {
        self.marked = b;
        self
    }
    pub fn clear(&mut self, term: &mut tui::term::Term) -> util::Result<()> {
        term.queue(cursor::MoveTo(
            self.region.col as u16,
            self.region.row as u16,
        ))?;

        term.queue(style::Print(" ".repeat(self.region.width)))?;

        Ok(())
    }
    pub fn draw(&mut self, term: &mut tui::term::Term, str: impl Into<String>) -> util::Result<()> {
        term.queue(cursor::MoveTo(
            self.region.col as u16,
            self.region.row as u16,
        ))?;

        // Collect the non-control characters of `str` into `display_str` upto a maximal terminal display width of `self.region.width`
        let mut display_str = String::new();
        {
            let mut display_width = 0;
            for (ix, ch) in str.into().char_indices() {
                if let Some(w) = ch.width() {
                    if display_width + w > self.region.width {
                        break;
                    }

                    if w > 0 {
                        display_str.push(ch);
                        display_width += w;
                    }
                }
            }
            display_str += &" ".repeat(self.region.width - display_width);
        }

        if self.marked {
            term.queue(style::PrintStyledContent(
                display_str
                    .with(style::Color::Green)
                    .on(style::Color::DarkGrey),
            ))?;
        } else {
            term.queue(style::Print(display_str))?;
        }

        Ok(())
    }
}
