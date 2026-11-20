use std::path::Path;
use std::sync::Arc;

/// Shared application state injected into Axum handlers.
#[derive(Clone)]
pub struct AppState {
    pub db: Arc<libsql::Database>,
    pub fonts: Arc<fontdb::Database>,
    pub app_env: String,
    pub base_url: String,
    pub version: &'static str,
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
