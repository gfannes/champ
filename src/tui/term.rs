use crate::{tui, util};

use crossterm::{cursor, event, style, terminal, ExecutableCommand, QueueableCommand};
use std::io::Write;

pub struct Term {
    stdout: std::io::Stdout,
    enabled: bool,
}

impl Term {
    pub fn new() -> util::Result<Term> {
        let mut term = Term {
            stdout: std::io::stdout(),
            enabled: false,
        };
        term.enable()?;
        Ok(term)
    }

    pub fn enable(&mut self) -> util::Result<()> {
        if !self.enabled {
            terminal::enable_raw_mode()?;
            self.stdout.queue(cursor::Hide {})?;
            self.stdout
                .execute(terminal::Clear(terminal::ClearType::All))?;
            self.stdout.execute(event::EnableMouseCapture)?;
            self.stdout.execute(event::EnableBracketedPaste)?;
            self.stdout.execute(event::EnableFocusChange)?;

            self.enabled = true;
        }
        Ok(())
    }

    pub fn disable(&mut self) -> util::Result<()> {
        if self.enabled {
            self.stdout.execute(cursor::Show {})?;
            self.stdout.execute(event::DisableMouseCapture)?;
            self.stdout.execute(event::DisableBracketedPaste)?;
            self.stdout.execute(event::DisableFocusChange)?;
            terminal::disable_raw_mode()?;

            self.enabled = false;
        }
        Ok(())
    }

    pub fn event(&mut self, timeout_ms: u64) -> util::Result<Option<tui::Event>> {
        if event::poll(std::time::Duration::from_millis(timeout_ms))? {
            let event = event::read()?;
            Ok(Some(event))
        } else {
            Ok(None)
        }
    }
    pub fn process_events(
        &mut self,
        timeout_ms: u64,
        mut ftor: impl FnMut(tui::Event) -> util::Result<()>,
    ) -> util::Result<()> {
        let mut timeout_ms = timeout_ms;
        while let Some(event) = self.event(timeout_ms)? {
            ftor(event)?;
            timeout_ms = 0;
        }

        Ok(())
    }

    pub fn clear(&mut self) -> util::Result<()> {
        self.stdout
            .queue(terminal::Clear(terminal::ClearType::All))?;
        Ok(())
    }

    pub fn move_to(&mut self, x: u16, y: u16) -> util::Result<()> {
        self.stdout.queue(cursor::MoveTo(x, y))?;
        Ok(())
    }

    pub fn print(&mut self, msg: impl Into<String>) -> util::Result<()> {
        self.stdout.queue(style::Print(msg.into()))?;
        Ok(())
    }

    pub fn flush(&mut self) -> util::Result<()> {
        self.stdout.flush()?;
        Ok(())
    }

    pub fn region(&self) -> util::Result<tui::layout::Region> {
        let (width, height) = crossterm::terminal::size()?;
        Ok(tui::layout::Region {
            row: 0,
            col: 0,
            width: width as usize,
            height: height as usize,
        })
    }
}

impl Drop for Term {
    fn drop(&mut self) {
        self.disable().unwrap()
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
