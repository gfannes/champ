use std::convert::Into;

pub struct Line {
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
            message: String::new(),
            timed_message: None,
        }
    }

    pub fn message(&self) -> &str {
        if let Some(timed_message) = &self.timed_message {
            let now = std::time::Instant::now();
            if now < timed_message.timeout {
                return &timed_message.message;
            }
        }
        return &self.message;
    }

    pub fn set_timed_message(&mut self, message: impl Into<String>, duration_ms: u64) {
        let timed_message = TimedMessage {
            timeout: std::time::Instant::now() + std::time::Duration::from_millis(duration_ms),
            message: message.into(),
        };
        self.timed_message = Some(timed_message);
    }
}
