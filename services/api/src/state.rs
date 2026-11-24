use std::path::Path;
use std::sync::Arc;

use tokio::sync::Semaphore;

use crate::config::{
    Config, DEFAULT_APP_STORE_URL, DEFAULT_REVENUECAT_BASE_URL, DEFAULT_SUPPORT_FORM_URL,
};
use crate::domain::sanitize::Sanitizer;
use crate::infra::db::SessionRepository;
use crate::infra::revenuecat::RevenueCatClient;

/// Shared application state injected into Axum handlers.
#[derive(Clone)]
pub struct AppState {
    pub repo: SessionRepository,
    pub fonts: Arc<fontdb::Database>,
    pub ogp_semaphore: Arc<Semaphore>,
    pub revenuecat: Arc<RevenueCatClient>,
    pub sanitizer: Arc<Sanitizer>,
    pub internal_cleanup_secret: Option<String>,
    pub report_form_url_template: Option<String>,
    pub support_form_url: String,
    pub app_store_url: String,
    pub app_env: String,
    pub base_url: String,
    pub version: &'static str,
}

impl AppState {
    pub fn from_config(db: libsql::Database, fonts: fontdb::Database, config: Config) -> Self {
        let db = Arc::new(db);
        let repo = if config.turso_database_url == ":memory:" {
            SessionRepository::new_pinned(db).expect("in-memory connection should open")
        } else {
            SessionRepository::new(db)
        };
        Self {
            repo,
            fonts: Arc::new(fonts),
            ogp_semaphore: Arc::new(Semaphore::new(config.ogp_max_concurrency)),
            revenuecat: Arc::new(RevenueCatClient::new(
                config.revenuecat_base_url,
                config.revenuecat_secret_api_key,
                config.revenuecat_fail_open,
            )),
            sanitizer: Arc::new(Sanitizer::new(&config.ng_words_extra)),
            internal_cleanup_secret: config.internal_cleanup_secret,
            report_form_url_template: config.report_form_url_template,
            support_form_url: config.support_form_url,
            app_store_url: config.app_store_url,
            app_env: config.app_env,
            base_url: config.base_url,
            version: env!("CARGO_PKG_VERSION"),
        }
    }

    pub fn for_testing(db: libsql::Database, fonts: fontdb::Database) -> Self {
        let repo = SessionRepository::new_pinned(Arc::new(db))
            .expect("test database connection should open");
        Self {
            repo,
            fonts: Arc::new(fonts),
            ogp_semaphore: Arc::new(Semaphore::new(4)),
            revenuecat: Arc::new(RevenueCatClient::new(
                DEFAULT_REVENUECAT_BASE_URL,
                None,
                true,
            )),
            sanitizer: Arc::new(Sanitizer::new(&[])),
            internal_cleanup_secret: Some("test-cleanup-secret".to_string()),
            report_form_url_template: Some(
                "https://docs.google.com/forms/d/e/example/viewform?usp=pp_url&entry.1371370885={session_id}"
                    .to_string(),
            ),
            support_form_url: DEFAULT_SUPPORT_FORM_URL.to_string(),
            app_store_url: DEFAULT_APP_STORE_URL.to_string(),
            app_env: "test".to_string(),
            base_url: "http://localhost:8080".to_string(),
            version: env!("CARGO_PKG_VERSION"),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum StartupError {
    #[error("database initialization failed: {0}")]
    Database(#[from] libsql::Error),
    #[error("required font file missing: {0}")]
    MissingFont(String),
    #[error("failed to load font '{path}': {source}")]
    FontLoad {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("expected font family '{0}' not registered after loading")]
    MissingFontFamily(String),
}

const FONT_FILES: [(&str, &str); 2] = [
    ("ShipporiMincho-Regular.ttf", "Shippori Mincho"),
    ("NotoSerifJP-Regular.otf", "Noto Serif JP"),
];

/// Open a local SQLite/libSQL database or remote Turso database.
pub async fn open_database(
    url: &str,
    auth_token: Option<&str>,
) -> Result<libsql::Database, StartupError> {
    if url == ":memory:" {
        return Ok(libsql::Builder::new_local(":memory:").build().await?);
    }

    if let Some(local_path) = url.strip_prefix("file:") {
        return Ok(libsql::Builder::new_local(local_path).build().await?);
    }

    if url.starts_with("libsql://") || url.starts_with("https://") || url.starts_with("http://") {
        let token = auth_token.unwrap_or_default().to_string();
        return Ok(libsql::Builder::new_remote(url.to_string(), token)
            .build()
            .await?);
    }

    Ok(libsql::Builder::new_local(url).build().await?)
}

/// Preload bundled Japanese OGP fonts into a shared `fontdb::Database`.
pub fn load_fonts(fonts_dir: &Path) -> Result<fontdb::Database, StartupError> {
    let mut db = fontdb::Database::new();

    for (filename, expected_family) in FONT_FILES {
        let path = fonts_dir.join(filename);
        if !path.is_file() {
            return Err(StartupError::MissingFont(path.display().to_string()));
        }

        db.load_font_file(&path)
            .map_err(|source| StartupError::FontLoad {
                path: path.display().to_string(),
                source,
            })?;

        let has_family = db.query(&fontdb::Query {
            families: &[fontdb::Family::Name(expected_family)],
            ..Default::default()
        });
        if has_family.is_none() {
            return Err(StartupError::MissingFontFamily(expected_family.to_string()));
        }
    }

    db.set_serif_family("Shippori Mincho");
    Ok(db)
}
