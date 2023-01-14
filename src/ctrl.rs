use crate::my::Result;
use crate::tui::*;

pub enum Command {
    Quit,
    Down,
    Up,
    In,
    Out,
}

pub struct Commander {
    mode: Mode,
    commands: Vec<Command>,
}

impl Commander {
    pub fn new() -> Commander {
        Commander {
            mode: Mode::Normal,
            commands: Vec::new(),
        }
    }

    pub fn process(&mut self, event: Event) -> Result<()> {
        match self.mode {
            Mode::Normal => match event {
                Event::Key(key) => match key.code {
                    KeyCode::Char(ch) => match ch {
                        'q' => self.commands.push(Command::Quit),
                        'j' => self.commands.push(Command::Down),
                        'k' => self.commands.push(Command::Up),
                        'h' => self.commands.push(Command::In),
                        'l' => self.commands.push(Command::Out),
                        _ => {}
                    },
                    _ => {}
                },
                _ => {}
            },
        }

        Ok(())
    }

    pub fn commands(&mut self) -> Vec<Command> {
        std::mem::take(&mut self.commands)
    }
}

enum Mode {
    Normal,
}
