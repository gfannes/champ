use crate::{config, util};

pub struct App {
    config: Config,
}

impl App {
    pub fn try_new(cli_args: config::CliArgs) -> util::Result<App> {
        let config = Config::load(cli_args)?;

        let app = App { config };
        Ok(app)
    }

    pub fn run(&self) -> util::Result<()> {
        if let Some(command) = self.config.command.as_ref() {
            match command {
                config::Command::List { verbose } => {
                    for root in &self.config.global.root {
                        println!("{:?}", root);
                    }
                }
            }
        }
        Ok(())
    }
}

struct Config {
    global: config::Global,
    command: Option<config::Command>,
}

impl Config {
    fn load(cli_args: config::CliArgs) -> util::Result<Config> {
        let global = config::Global::load(&cli_args)?;

        let mut config = Config {
            global,
            command: cli_args.command,
        };

        Ok(config)
    }
}
