use crate::{cli, fail, util};
use dirs;
use serde;
use std::path;
use toml;

#[derive(serde::Deserialize, Debug)]
pub struct Config {
    pub test: Option<String>,
}

pub struct Settings {
    pub mainloop_timeout_ms: u64,
    pub log_level: String,
    pub config_fp: path::PathBuf,
    pub config: Config,
}

impl Settings {
    pub fn load(cli_options: &cli::Options) -> util::Result<Settings> {
        let config_fp;
        if let Some(fp) = &cli_options.config {
            config_fp = Some(fp.to_owned());
        } else {
            config_fp = dirs::config_dir().map(|d| d.join("champ/config.toml"));
            if let Some(fp) = &config_fp {
                if let Some(dir) = fp.parent() {
                    if !dir.exists() {
                        std::fs::create_dir_all(dir)?;
                    } else if !dir.is_dir() {
                        fail!("Expected '{}' to be absent or a directory", dir.display());
                    }

                    if !fp.exists() {
                        std::fs::write(fp, "")?;
                    } else if !fp.is_file() {
                        fail!("Expected '{}' to be absent or a file", fp.display());
                    }
                }
            }
        }
        let config_fp =
            config_fp.ok_or(util::Error::create("Could not determine config filepath"))?;
        if !config_fp.is_file() {
            fail!("Could not find config file '{}'", config_fp.display());
        }

        let content = std::fs::read(&config_fp)?;
        let content = std::str::from_utf8(&content)?;
        let config: Config = toml::from_str(content)?;

        let settings = Settings {
            mainloop_timeout_ms: 100,
            log_level: "info".to_owned(),
            config_fp,
            config,
        };
        Ok(settings)
    }
}
