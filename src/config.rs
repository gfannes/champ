use crate::{cli, util};

pub struct Settings {
    pub mainloop_timeout_ms: u64,
}

impl Settings {
    pub fn load(cli_options: &cli::Options) -> util::Result<Settings> {
        let settings = Settings {
            mainloop_timeout_ms: 100,
        };
        Ok(settings)
    }
}
