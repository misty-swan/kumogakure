use std::time::Duration;

use axum::http::StatusCode;
use axum::middleware;
use axum::routing::{get, post};
use axum::Router;
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::compression::CompressionLayer;
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::TraceLayer;

use crate::handlers;
use crate::middleware::security_headers::apply_baseline_security_headers;
use crate::state::AppState;

const MAX_REQUEST_BODY_BYTES: usize = 64 * 1024;

/// Build the Axum application router with all endpoints and HTTP middleware.
pub fn build_router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(handlers::health::health))
        .route("/api/v1/sessions", post(handlers::sessions::create_session))
        .route(
            "/api/v1/sessions/{id}/finish",
            post(handlers::sessions::finish_session),
        )
        .route("/api/v1/stats/active", get(handlers::stats::active_stats))
        .route("/s/{id}", get(handlers::public_page::absence_page))
        .route("/ogp/{file}", get(handlers::ogp::ogp_image))
        .route("/legal/privacy", get(handlers::public_page::legal_privacy))
        .route("/legal/terms", get(handlers::public_page::legal_terms))
        .route("/internal/cleanup", post(handlers::internal::cleanup))
        .with_state(state)
        .layer(middleware::from_fn(apply_baseline_security_headers))
        .layer(RequestBodyLimitLayer::new(MAX_REQUEST_BODY_BYTES))
        .layer(CompressionLayer::new())
        .layer(CatchPanicLayer::new())
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            Duration::from_secs(15),
        ))
        .layer(TraceLayer::new_for_http())
}
