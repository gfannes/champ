use crate::my;
use crate::tui;
use crossterm::{cursor, event, style, terminal, ExecutableCommand, QueueableCommand};
use std::io::Write;

pub struct Term {
    stdout: std::io::Stdout,
}

impl Term {
    pub fn new() -> my::Result<Term> {
        let mut stdout = std::io::stdout();
        terminal::enable_raw_mode()?;
        stdout.queue(cursor::Hide {})?;
        stdout.execute(terminal::Clear(terminal::ClearType::All))?;
        stdout.execute(event::EnableMouseCapture)?;
        stdout.execute(event::EnableBracketedPaste)?;
        stdout.execute(event::EnableFocusChange)?;
        Ok(Term { stdout })
    }

    pub fn event(&mut self) -> my::Result<Option<tui::Event>> {
        if event::poll(std::time::Duration::from_millis(1000))? {
            let event = event::read()?;
            Ok(Some(event))
        } else {
            Ok(None)
        }
    }

    pub fn clear(&mut self) -> my::Result<()> {
        self.stdout
            .queue(terminal::Clear(terminal::ClearType::All))?;
        Ok(())
    }

    pub fn move_to(&mut self, x: u16, y: u16) -> my::Result<()> {
        self.stdout.queue(cursor::MoveTo(x, y))?;
        Ok(())
    }

    pub fn print(&mut self, msg: impl Into<String>) -> my::Result<()> {
        self.stdout.queue(style::Print(msg.into()))?;
        Ok(())
    }

    pub fn flush(&mut self) -> my::Result<()> {
        self.stdout.flush()?;
        Ok(())
    }

    pub fn region(&self) -> my::Result<tui::Region> {
        let (width, height) = crossterm::terminal::size()?;
        Ok(tui::Region {
            row: 0,
            col: 0,
            width: width as usize,
            height: height as usize,
        })
    }
}

impl Drop for Term {
    fn drop(&mut self) {
        self.stdout.execute(cursor::Show {}).unwrap();
        self.stdout.execute(event::DisableMouseCapture).unwrap();
        self.stdout.execute(event::DisableBracketedPaste).unwrap();
        self.stdout.execute(event::DisableFocusChange).unwrap();
        terminal::disable_raw_mode().unwrap();
    }
}

impl std::ops::Deref for Term {
    type Target = std::io::Stdout;
    fn deref(&self) -> &Self::Target {
        &self.stdout
    }
}

impl std::ops::DerefMut for Term {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.stdout
    }
}
