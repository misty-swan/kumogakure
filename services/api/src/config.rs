use std::env;
use std::path::PathBuf;

/// Runtime configuration parsed from environment variables.
#[derive(Debug, Clone)]
pub struct Config {
    pub port: u16,
    pub app_env: String,
    pub base_url: String,
    pub turso_database_url: String,
    pub turso_auth_token: Option<String>,
    pub fonts_dir: PathBuf,
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("invalid PORT value '{0}'")]
    InvalidPort(String),
    #[error("TURSO_AUTH_TOKEN must be set when connecting to remote Turso ({0})")]
    MissingTursoAuthToken(String),
}

impl Config {
    /// Load configuration from process environment variables with safe local defaults.
    pub fn from_env() -> Result<Self, ConfigError> {
        let port = match env::var("PORT") {
            Ok(raw) => raw
                .parse::<u16>()
                .map_err(|_| ConfigError::InvalidPort(raw))?,
            Err(_) => 8080,
        };

        let app_env = env::var("APP_ENV").unwrap_or_else(|_| "local".to_string());
        let base_url = env::var("BASE_URL").unwrap_or_else(|_| "http://localhost:8080".to_string());
        let turso_database_url =
            env::var("TURSO_DATABASE_URL").unwrap_or_else(|_| "file:./local.db".to_string());

        let turso_auth_token = env::var("TURSO_AUTH_TOKEN")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());

        let is_remote = turso_database_url.starts_with("libsql://")
            || turso_database_url.starts_with("https://")
            || turso_database_url.starts_with("http://");

        if is_remote && turso_auth_token.is_none() {
            return Err(ConfigError::MissingTursoAuthToken(turso_database_url));
        }

        let fonts_dir = env::var("FONTS_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("assets/fonts"));

        Ok(Self {
            port,
            app_env,
            base_url,
            turso_database_url,
            turso_auth_token,
            fonts_dir,
        })
    }
}
