use std::convert::Into;

pub struct Line {
    pub message: String,
    pub timed_messages: Vec<TimedMessage>,
}

pub struct TimedMessage {
    pub timeout: std::time::Instant,
    pub message: String,
}

impl Line {
    pub fn new() -> Line {
        Line {
            message: String::new(),
            timed_messages: Vec::new(),
        }
    }

    pub fn add_timed_message(&mut self, message: impl Into<String>, duration_ms: u64) {
        self.timed_messages.push(TimedMessage {
            timeout: std::time::Instant::now() + std::time::Duration::from_millis(duration_ms),
            message: message.into(),
        });
    }
}
