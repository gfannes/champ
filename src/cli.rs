use crate::{config, util};

pub struct App {}

impl App {
    pub fn try_new(cli_args: &config::CliArgs) -> util::Result<App> {
        let app = App {};
        Ok(app)
    }

    pub fn run(&self) -> util::Result<()> {
        println!("cli.App.run()");
        Ok(())
    }
}
