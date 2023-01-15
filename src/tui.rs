use crate::data;
pub use crate::my::Result;

pub use crossterm::event::{Event, KeyCode};
use crossterm::{
    cursor, event,
    style::{self, Color, Stylize},
    terminal, ExecutableCommand, QueueableCommand,
};
use std::io::Write;

pub struct Tui {
    stdout: std::io::Stdout,
}

impl Tui {
    pub fn new() -> Result<Tui> {
        let mut stdout = std::io::stdout();
        terminal::enable_raw_mode()?;
        stdout.queue(cursor::Hide {})?;
        stdout.execute(terminal::Clear(terminal::ClearType::All))?;
        stdout.execute(event::EnableMouseCapture)?;
        stdout.execute(event::EnableBracketedPaste)?;
        stdout.execute(event::EnableFocusChange)?;
        Ok(Tui { stdout })
    }

    pub fn event(&mut self) -> Result<Option<Event>> {
        if event::poll(std::time::Duration::from_millis(10))? {
            let event = event::read()?;
            Ok(Some(event))
        } else {
            Ok(None)
        }
    }

    pub fn clear(&mut self) -> Result<()> {
        self.stdout
            .queue(terminal::Clear(terminal::ClearType::All))?;
        Ok(())
    }

    pub fn move_to(&mut self, x: u16, y: u16) -> Result<()> {
        self.stdout.queue(cursor::MoveTo(x, y))?;
        Ok(())
    }

    pub fn print(&mut self, msg: impl Into<String>) -> Result<()> {
        self.stdout.queue(style::Print(msg.into()))?;
        Ok(())
    }

    pub fn flush(&mut self) -> Result<()> {
        self.stdout.flush()?;
        Ok(())
    }

    pub fn region(&self) -> Result<Region> {
        let (width, height) = crossterm::terminal::size()?;
        Ok(Region {
            row: 0,
            col: 0,
            width: width as usize,
            height: height as usize,
        })
    }
}

impl Drop for Tui {
    fn drop(&mut self) {
        self.stdout.execute(cursor::Show {}).unwrap();
        self.stdout.execute(event::DisableMouseCapture).unwrap();
        self.stdout.execute(event::DisableBracketedPaste).unwrap();
        self.stdout.execute(event::DisableFocusChange).unwrap();
        terminal::disable_raw_mode().unwrap();
    }
}

impl std::ops::Deref for Tui {
    type Target = std::io::Stdout;
    fn deref(&self) -> &Self::Target {
        &self.stdout
    }
}

impl std::ops::DerefMut for Tui {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.stdout
    }
}

pub struct List {
    region: Region,
}

#[derive(Debug, Copy, Clone)]
pub struct Region {
    pub row: usize,
    pub col: usize,
    pub width: usize,
    pub height: usize,
}

pub struct Path {
    region: Region,
}

impl Path {
    pub fn new(region: Region) -> Path {
        Path { region }
    }
    pub fn draw(&mut self, tui: &mut Tui, path: &data::Path) -> Result<()> {
        tui.queue(cursor::MoveTo(
            self.region.row as u16,
            self.region.col as u16,
        ))?;

        let mut str = format!("{}", path);
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

        tui.queue(style::Print(str))?;

        Ok(())
    }
}
