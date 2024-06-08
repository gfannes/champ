use crate::{tui, util};

#[derive(Copy, Clone, Debug)]
pub enum Mode {
    Normal,
    Filter,
}

pub enum Command {
    Quit,
    In,
    Out,
    Down,
    Up,
    DownDown,
    UpUp,
    Top,
    Bottom,
    Shell,
    Delete,
    SwitchTab(usize),
    SwitchMode(Mode),
}

pub struct Commander {
    mode: Mode,
    pub str: String,
    commands: Vec<Command>,
}

impl Commander {
    pub fn new() -> Commander {
        let mut res = Commander {
            mode: Mode::Normal,
            str: String::new(),
            commands: Vec::new(),
        };
        res.commands.push(Command::SwitchMode(res.mode));
        res
    }

    pub fn process(&mut self, event: tui::Event) -> util::Result<()> {
        match self.mode {
            Mode::Normal => match event {
                tui::Event::Key(key) => match key.code {
                    tui::KeyCode::Char(ch) => match ch {
                        'q' => self.commands.push(Command::Quit),

                        '/' => {
                            self.mode = Mode::Filter;
                            self.commands.push(Command::SwitchMode(self.mode));
                        }

                        'j' => self.commands.push(Command::Down),
                        'k' => self.commands.push(Command::Up),
                        'h' => self.commands.push(Command::In),
                        'l' => self.commands.push(Command::Out),
                        'e' => self.commands.push(Command::Out),
                        'g' => self.commands.push(Command::Top),
                        'G' => self.commands.push(Command::Bottom),

                        ';' => self.commands.push(Command::Shell),
                        'w' => self.commands.push(Command::Shell),

                        'd' => self.commands.push(Command::Delete),

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
                    tui::KeyCode::Down => self.commands.push(Command::Down),
                    tui::KeyCode::Up => self.commands.push(Command::Up),
                    tui::KeyCode::PageDown => self.commands.push(Command::DownDown),
                    tui::KeyCode::PageUp => self.commands.push(Command::UpUp),
                    tui::KeyCode::Left => self.commands.push(Command::In),
                    tui::KeyCode::Right => self.commands.push(Command::Out),
                    tui::KeyCode::Enter => self.commands.push(Command::Out),

                    tui::KeyCode::Esc => {}
                    _ => {}
                },
                _ => {}
            },
            Mode::Filter => match event {
                tui::Event::Key(key) => match key.code {
                    tui::KeyCode::Char(ch) => match ch {
                        ';' => {
                            self.mode = Mode::Normal;
                            self.commands.push(Command::SwitchMode(self.mode));
                            self.commands.push(Command::Shell);
                        }
                        _ => self.str.push(ch),
                    },
                    tui::KeyCode::Down => self.commands.push(Command::Down),
                    tui::KeyCode::Up => self.commands.push(Command::Up),
                    tui::KeyCode::Left => self.commands.push(Command::In),
                    tui::KeyCode::Right => self.commands.push(Command::Out),
                    tui::KeyCode::Enter => self.commands.push(Command::Out),
                    tui::KeyCode::Backspace => {
                        if !self.str.is_empty() {
                            self.str.pop();
                        }
                    }
                    tui::KeyCode::Esc => {
                        if self.str.is_empty() {
                            self.mode = Mode::Normal;
                            self.commands.push(Command::SwitchMode(self.mode));
                        } else {
                            self.str.clear();
                        }
                    }
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
