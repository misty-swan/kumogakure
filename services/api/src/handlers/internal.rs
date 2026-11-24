use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use serde::Serialize;

use crate::domain::session::{current_unix_seconds, CLEANUP_GRACE_SECONDS};
use crate::domain::token::verify_secret_constant_time;
use crate::error::AppError;
use crate::state::AppState;

#[derive(Debug, Serialize)]
pub struct CleanupResponse {
    pub deleted_count: u64,
    pub executed_at: i64,
}

/// `POST /internal/cleanup`
pub async fn cleanup(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<(StatusCode, Json<CleanupResponse>), AppError> {
    let expected = state
        .internal_cleanup_secret
        .as_deref()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| AppError::unauthorized("cleanup 認証が構成されていません。"))?;

    let provided = headers
        .get("X-Internal-Secret")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| AppError::unauthorized("X-Internal-Secret ヘッダが必要です。"))?;

    if !verify_secret_constant_time(provided, expected) {
        return Err(AppError::unauthorized("X-Internal-Secret が不正です。"));
    }

    let now = current_unix_seconds();
    let cutoff = now - CLEANUP_GRACE_SECONDS;
    let deleted_count = state.repo.delete_expired_before(cutoff).await?;

    tracing::info!(
        deleted_count,
        executed_at = now,
        "executed expired session cleanup"
    );

    Ok((
        StatusCode::OK,
        Json(CleanupResponse {
            deleted_count,
            executed_at: now,
        }),
    ))
}
