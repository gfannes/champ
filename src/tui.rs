pub use crate::my::Result;

use crossterm::{
    cursor, event,
    style::{self, Color, Stylize},
    terminal, ExecutableCommand, QueueableCommand,
};
use std::io::Write;

pub struct Region {
    row: usize,
    col: usize,
    width: usize,
    height: usize,
}

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
}

impl Drop for Tui {
    fn drop(&mut self) {
        println!("\nDropping Tui");
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

pub fn test() -> Result<()> {
    let mut a = Tui::new()?;

    for i in 0..1000 {
        if event::poll(std::time::Duration::from_millis(10))? {
            let event = event::read()?;
            write!(a.stdout, "event: {:?}\r\n", event)?;
            match event {
                event::Event::FocusGained => {}
                event::Event::FocusLost => {}
                event::Event::Key(event) => {
                    if event.code == event::KeyCode::Char('q') {
                        return Ok(());
                    }
                }
                event::Event::Mouse(event) => {}
                event::Event::Paste(str) => {}
                event::Event::Resize(cols, roms) => {}
            }
        }
        if true {
            for y in 0..40 {
                for x in 0..150 {
                    if (y == 0 || y == 40 - 1) || (x == 0 || x == 150 - 1) {
                        // in this loop we are more efficient by not flushing the buffer.
                        a.queue(cursor::MoveTo(x, y))?
                            .queue(style::PrintStyledContent(
                                "#".with(Color::Rgb {
                                    r: (x + i) as u8,
                                    g: y as u8,
                                    b: 120,
                                })
                                .on(Color::Rgb {
                                    r: 120,
                                    g: x as u8,
                                    b: (y + i) as u8,
                                }),
                            ))?;
                    }
                }
            }
            a.flush()?;
        }
    }

    // a.a.queue(cursor::Show {})?;

    Ok(())
}
