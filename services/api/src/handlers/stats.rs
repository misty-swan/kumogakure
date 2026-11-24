use axum::extract::State;
use axum::http::header::CACHE_CONTROL;
use axum::http::{HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;

use crate::domain::session::current_unix_seconds;
use crate::error::AppError;
use crate::state::AppState;

#[derive(Debug, Serialize)]
struct ActiveStatsResponse {
    active_count: i64,
    sampled_at: i64,
}

/// `GET /api/v1/stats/active`
pub async fn active_stats(State(state): State<AppState>) -> Result<Response, AppError> {
    let now = current_unix_seconds();
    let active_count = state.repo.count_active(now).await?;

    let mut res = (
        StatusCode::OK,
        Json(ActiveStatsResponse {
            active_count,
            sampled_at: now,
        }),
    )
        .into_response();

    res.headers_mut().insert(
        CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=30, s-maxage=30"),
    );

    Ok(res)
}
