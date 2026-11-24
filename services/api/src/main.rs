use std::net::SocketAddr;

use kumogakure_api::build_router;
use kumogakure_api::config::Config;
use kumogakure_api::state::{load_fonts, open_database, AppState};
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,kumogakure_api=debug"));
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(filter)
        .with_current_span(false)
        .init();

    let config = Config::from_env()?;
    let db = open_database(
        &config.turso_database_url,
        config.turso_auth_token.as_deref(),
    )
    .await?;
    let fonts = load_fonts(&config.fonts_dir)?;
    let font_faces = fonts.faces().count();

    tracing::info!(
        app_env = %config.app_env,
        port = config.port,
        font_faces = font_faces,
        "initialized Kumogakure API state"
    );

    let state = AppState::from_config(db, fonts, config.clone());

    let app = build_router(state);
    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    let listener = TcpListener::bind(addr).await?;
    tracing::info!(%addr, "listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };

    #[cfg(unix)]
    let terminate = async {
        if let Ok(mut sig) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            sig.recv().await;
        }
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
    tracing::info!("shutdown signal received");
}
