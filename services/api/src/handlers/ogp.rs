use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::header::{CACHE_CONTROL, CONTENT_TYPE};
use axum::http::{HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};

use crate::domain::session::current_unix_seconds;
use crate::domain::token::is_valid_session_id;
use crate::error::AppError;
use crate::middleware::security_headers::{NOINDEX_NOFOLLOW, X_ROBOTS_TAG};
use crate::ogp::renderer::render_ogp_png;
use crate::state::AppState;

/// `GET /ogp/{file}` (expects `<10-char-nanoid>.png`).
pub async fn ogp_image(
    State(state): State<AppState>,
    Path(file): Path<String>,
) -> Result<Response, AppError> {
    let Some(id) = file.strip_suffix(".png") else {
        return Ok(ogp_error_response(StatusCode::NOT_FOUND));
    };

    if !is_valid_session_id(id) {
        return Ok(ogp_error_response(StatusCode::NOT_FOUND));
    }

    let Some(session) = state.repo.find_by_id(id).await? else {
        return Ok(ogp_error_response(StatusCode::NOT_FOUND));
    };

    if !session.is_public {
        return Ok(ogp_error_response(StatusCode::NOT_FOUND));
    }

    let now = current_unix_seconds();
    if session.is_expired(now) {
        return Ok(ogp_error_response(StatusCode::GONE));
    }

    let png_bytes = render_ogp_png(
        &session,
        Arc::clone(&state.fonts),
        Arc::clone(&state.ogp_semaphore),
    )
    .await
    .map_err(|err| AppError::Internal(format!("OGP rendering failed: {err}")))?;

    let mut res = (StatusCode::OK, png_bytes).into_response();
    let headers = res.headers_mut();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("image/png"));
    headers.insert(
        CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=86400, s-maxage=86400, immutable"),
    );
    headers.insert(
        X_ROBOTS_TAG.clone(),
        HeaderValue::from_static(NOINDEX_NOFOLLOW),
    );

    Ok(res)
}

fn ogp_error_response(status: StatusCode) -> Response {
    let mut res = status.into_response();
    let headers = res.headers_mut();
    headers.insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
    headers.insert(
        X_ROBOTS_TAG.clone(),
        HeaderValue::from_static(NOINDEX_NOFOLLOW),
    );
    res
}
