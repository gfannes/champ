use crate::my::Result;
use crate::tui::*;

pub enum Command {
    Quit,
    Down,
    Up,
    In,
    Out,
    SwitchTab(usize),
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
                        '0' => self.commands.push(Command::SwitchTab(0)),
                        '1' => self.commands.push(Command::SwitchTab(1)),
                        '2' => self.commands.push(Command::SwitchTab(2)),
                        '3' => self.commands.push(Command::SwitchTab(3)),
                        '4' => self.commands.push(Command::SwitchTab(4)),
                        '5' => self.commands.push(Command::SwitchTab(5)),
                        '6' => self.commands.push(Command::SwitchTab(6)),
                        '7' => self.commands.push(Command::SwitchTab(7)),
                        '8' => self.commands.push(Command::SwitchTab(8)),
                        '9' => self.commands.push(Command::SwitchTab(9)),
                        _ => {}
                    },
                    KeyCode::Down => self.commands.push(Command::Down),
                    KeyCode::Up => self.commands.push(Command::Up),
                    KeyCode::Left => self.commands.push(Command::In),
                    KeyCode::Right => self.commands.push(Command::Out),
                    KeyCode::Enter => self.commands.push(Command::Out),
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
