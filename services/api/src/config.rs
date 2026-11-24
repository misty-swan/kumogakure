use std::env;
use std::path::PathBuf;

pub const DEFAULT_SUPPORT_FORM_URL: &str =
    "https://docs.google.com/forms/d/e/1FAIpQLScOjICc8nN83rTRGXd2oYbvBicAxNB8yvrFXsNFjE00xLIqgQ/viewform";
pub const DEFAULT_APP_STORE_URL: &str =
    "https://apps.apple.com/?utm_source=absence_card&utm_medium=web";
pub const DEFAULT_REVENUECAT_BASE_URL: &str = "https://api.revenuecat.com";

/// Runtime configuration parsed from environment variables.
#[derive(Debug, Clone)]
pub struct Config {
    pub port: u16,
    pub app_env: String,
    pub base_url: String,
    pub turso_database_url: String,
    pub turso_auth_token: Option<String>,
    pub fonts_dir: PathBuf,
    pub revenuecat_secret_api_key: Option<String>,
    pub revenuecat_base_url: String,
    pub revenuecat_fail_open: bool,
    pub internal_cleanup_secret: Option<String>,
    pub report_form_url_template: Option<String>,
    pub support_form_url: String,
    pub app_store_url: String,
    pub ogp_max_concurrency: usize,
    pub ng_words_extra: Vec<String>,
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
        let base_url = env::var("BASE_URL")
            .unwrap_or_else(|_| "http://localhost:8080".to_string())
            .trim()
            .trim_end_matches('/')
            .to_string();

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

        let revenuecat_secret_api_key = env::var("REVENUECAT_SECRET_API_KEY")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty() && v != "PLACEHOLDER_REPLACE_ME");

        let revenuecat_base_url = env::var("REVENUECAT_BASE_URL")
            .ok()
            .map(|v| v.trim().trim_end_matches('/').to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| DEFAULT_REVENUECAT_BASE_URL.to_string());

        let revenuecat_fail_open = env::var("REVENUECAT_FAIL_OPEN")
            .ok()
            .map(|v| {
                let norm = v.trim().to_ascii_lowercase();
                !matches!(norm.as_str(), "false" | "0")
            })
            .unwrap_or(true);

        let internal_cleanup_secret = env::var("INTERNAL_CLEANUP_SECRET")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());

        let report_form_url_template = env::var("REPORT_FORM_URL_TEMPLATE")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());

        let support_form_url = env::var("SUPPORT_FORM_URL")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| DEFAULT_SUPPORT_FORM_URL.to_string());

        let app_store_url = env::var("APP_STORE_URL")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| DEFAULT_APP_STORE_URL.to_string());

        let ogp_max_concurrency = env::var("OGP_MAX_CONCURRENCY")
            .ok()
            .and_then(|v| v.trim().parse::<usize>().ok())
            .unwrap_or(4)
            .max(1);

        let ng_words_extra = env::var("NG_WORDS_EXTRA")
            .ok()
            .map(|raw| {
                raw.split(',')
                    .map(|part| part.trim().to_string())
                    .filter(|part| !part.is_empty())
                    .collect()
            })
            .unwrap_or_default();

        Ok(Self {
            port,
            app_env,
            base_url,
            turso_database_url,
            turso_auth_token,
            fonts_dir,
            revenuecat_secret_api_key,
            revenuecat_base_url,
            revenuecat_fail_open,
            internal_cleanup_secret,
            report_form_url_template,
            support_form_url,
            app_store_url,
            ogp_max_concurrency,
            ng_words_extra,
        })
    }
}
