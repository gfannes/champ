use crate::my::Result;

pub mod cli {
    use crate::my::Result;

    pub struct Options {
        pub help: bool,
        pub verbose: u32,
    }

    impl Options {
        fn new() -> Options {
            let options = Options {
                help: false,
                verbose: 0,
            };

            return options;
        }

        pub fn parse() -> Result<Options> {
            let options = Options::new();
            return Ok(options);
        }
    }
}

pub struct Settings {}

impl Settings {
    pub fn load(cli_options: &cli::Options) -> Result<Settings> {
        let settings = Settings {};
        Ok(settings)
    }
}
