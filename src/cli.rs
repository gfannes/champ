use crate::my;

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

    pub fn parse() -> my::Result<Options> {
        let options = Options::new();
        return Ok(options);
    }
}
