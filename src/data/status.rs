use crate::ctrl::Mode;
use std::convert::Into;

pub struct Line {
    pub mode: Mode,
    pub message: String,
    pub timed_message: Option<TimedMessage>,
}

pub struct TimedMessage {
    pub timeout: std::time::Instant,
    pub message: String,
}

impl Line {
    pub fn new() -> Line {
        Line {
            mode: Mode::Normal,
            message: String::new(),
            timed_message: None,
        }
    }

    pub fn message(&self) -> String {
        let mut msg = String::new();

        match self.mode {
            Mode::Normal => msg += "NOR",
            Mode::Filter => msg += "FLT",
        }

        msg.push(' ');
        msg += &self.message;

        if let Some(timed_message) = &self.timed_message {
            let now = std::time::Instant::now();
            if now < timed_message.timeout {
                msg.push(' ');
                msg += &timed_message.message;
            }
        }

        return msg;
    }

    pub fn set_timed_message(&mut self, message: impl Into<String>, duration_ms: u64) {
        let timed_message = TimedMessage {
            timeout: std::time::Instant::now() + std::time::Duration::from_millis(duration_ms),
            message: message.into(),
        };
        self.timed_message = Some(timed_message);
    }
}
