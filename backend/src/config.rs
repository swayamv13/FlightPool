use sqlx::postgres::PgConnectOptions;
use std::str::FromStr;
use std::{env, io};

#[derive(Clone, PartialEq, Eq)]
pub struct Config {
    pub port: u16,
    pub database_url: String,
}

impl Config {
    pub fn load_dotenv() -> Result<(), Box<dyn std::error::Error>> {
        match dotenvy::dotenv() {
            Ok(_) => Ok(()),
            Err(dotenvy::Error::Io(error)) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }

    pub fn from_env() -> Result<Self, io::Error> {
        let port = match env::var("PORT") {
            Ok(value) => value.parse::<u16>().map_err(|error| {
                io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("PORT must be a valid port number: {error}"),
                )
            })?,
            Err(env::VarError::NotPresent) => 3000,
            Err(error) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("failed to read PORT: {error}"),
                ));
            }
        };

        let database_url = match env::var("DATABASE_URL") {
            Ok(value) => value,
            Err(env::VarError::NotPresent) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "DATABASE_URL is required",
                ));
            }
            Err(error) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("failed to read DATABASE_URL: {error}"),
                ));
            }
        };

        PgConnectOptions::from_str(&database_url)
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "DATABASE_URL is invalid"))?;

        Ok(Self { port, database_url })
    }
}
