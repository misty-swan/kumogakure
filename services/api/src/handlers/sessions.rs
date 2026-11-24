use axum::extract::{Path, State};
use axum::http::header::AUTHORIZATION;
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::domain::catalog::{is_preset_message, CardStyle, ThemeId};
use crate::domain::sanitize::{MAX_DISPLAY_NAME_GRAPHEMES, MAX_MESSAGE_GRAPHEMES};
use crate::domain::session::{
    current_unix_seconds, parse_timezone, validate_duration_minutes, validate_user_uuid,
    SessionRecord, SessionStatus, SESSION_TTL_SECONDS,
};
use crate::domain::token::{
    generate_owner_token, generate_session_id, is_valid_session_id, verify_owner_token,
};
use crate::error::{AppError, AppJson};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct CreateSessionRequest {
    pub user_uuid: String,
    pub duration_minutes: i64,
    pub theme_id: String,
    pub card_style: Option<String>,
    pub hide_watermark: Option<bool>,
    pub is_public: bool,
    pub is_custom_message: Option<bool>,
    pub display_name: Option<String>,
    pub message: Option<String>,
    pub timezone: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct CreateSessionResponse {
    pub id: String,
    pub owner_token: String,
    pub status: &'static str,
    pub started_at: i64,
    pub ends_at: i64,
    pub expires_at: i64,
    pub share_url: Option<String>,
    pub ogp_image_url: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct FinishSessionRequest {
    pub outcome: String,
}

#[derive(Debug, Serialize)]
pub struct FinishSessionResponse {
    pub id: String,
    pub status: &'static str,
    pub finished_at: i64,
}

/// `POST /api/v1/sessions`
pub async fn create_session(
    State(state): State<AppState>,
    AppJson(payload): AppJson<CreateSessionRequest>,
) -> Result<(StatusCode, Json<CreateSessionResponse>), AppError> {
    let user_uuid = validate_user_uuid(&payload.user_uuid)?;
    let duration_minutes = validate_duration_minutes(payload.duration_minutes)?;

    let theme_id = ThemeId::parse(payload.theme_id.trim())
        .ok_or_else(|| AppError::validation("theme_id", "未知の theme_id が指定されました。"))?;

    let card_style = match payload.card_style.as_deref() {
        None => CardStyle::WashiClassic,
        Some(raw) => CardStyle::parse(raw.trim()).ok_or_else(|| {
            AppError::validation("card_style", "未知の card_style が指定されました。")
        })?,
    };

    let hide_watermark = payload.hide_watermark.unwrap_or(false);
    let is_custom_message = payload.is_custom_message.unwrap_or(false);
    let tz = parse_timezone(payload.timezone.as_deref())?;

    let display_name = state.sanitizer.sanitize_text(
        payload.display_name.as_deref(),
        MAX_DISPLAY_NAME_GRAPHEMES,
        "display_name",
    )?;
    let message = state.sanitizer.sanitize_text(
        payload.message.as_deref(),
        MAX_MESSAGE_GRAPHEMES,
        "message",
    )?;

    if let Some(pro_field) = detect_pro_field(
        theme_id,
        card_style,
        hide_watermark,
        is_custom_message,
        message.as_deref(),
    ) {
        let is_pro = state.revenuecat.verify_hermit_pro(&user_uuid).await?;
        if !is_pro {
            return Err(AppError::ProRequired { field: pro_field });
        }
    }

    let id = generate_session_id();
    let (owner_token, owner_token_hash) = generate_owner_token();
    let started_at = current_unix_seconds();
    let ends_at = started_at + duration_minutes * 60;
    let expires_at = started_at + SESSION_TTL_SECONDS;

    let record = SessionRecord {
        id: id.clone(),
        user_uuid,
        owner_token_hash,
        display_name,
        message,
        theme_id,
        card_style,
        hide_watermark,
        is_public: payload.is_public,
        timezone: tz.name().to_string(),
        status: SessionStatus::Active,
        started_at,
        ends_at,
        finished_at: None,
        expires_at,
    };

    state.repo.create_session(&record, started_at).await?;

    let (share_url, ogp_image_url) = if payload.is_public {
        (
            Some(format!("{}/s/{}", state.base_url, id)),
            Some(format!("{}/ogp/{}.png", state.base_url, id)),
        )
    } else {
        (None, None)
    };

    tracing::info!(
        session_id = %id,
        is_public = payload.is_public,
        theme_id = %theme_id,
        card_style = %card_style,
        duration_minutes,
        "created detox session"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateSessionResponse {
            id,
            owner_token,
            status: SessionStatus::Active.as_str(),
            started_at,
            ends_at,
            expires_at,
            share_url,
            ogp_image_url,
        }),
    ))
}

/// `POST /api/v1/sessions/{id}/finish`
pub async fn finish_session(
    State(state): State<AppState>,
    Path(id): Path<String>,
    headers: HeaderMap,
    AppJson(payload): AppJson<FinishSessionRequest>,
) -> Result<(StatusCode, Json<FinishSessionResponse>), AppError> {
    let bearer_token = extract_bearer_token(&headers)?;

    let target_status = match payload.outcome.trim() {
        "completed" => SessionStatus::Completed,
        "canceled" => SessionStatus::Canceled,
        _ => {
            return Err(AppError::validation(
                "outcome",
                "outcome は 'completed' または 'canceled' を指定してください。",
            ));
        }
    };

    if !is_valid_session_id(&id) {
        return Err(AppError::SessionNotFound);
    }

    let existing = state
        .repo
        .find_by_id(&id)
        .await?
        .ok_or(AppError::SessionNotFound)?;

    if !verify_owner_token(bearer_token, &existing.owner_token_hash) {
        return Err(AppError::unauthorized("owner_token が不正です。"));
    }

    // Idempotent behavior: if already finished, return existing state without overwriting.
    if existing.status != SessionStatus::Active {
        return Ok((
            StatusCode::OK,
            Json(FinishSessionResponse {
                id: existing.id,
                status: existing.status.as_str(),
                finished_at: existing.finished_at.unwrap_or(existing.started_at),
            }),
        ));
    }

    let now = current_unix_seconds();
    let updated = state
        .repo
        .finish_session_if_active(&id, target_status, now)
        .await?
        .ok_or(AppError::SessionNotFound)?;

    tracing::info!(
        session_id = %updated.id,
        status = updated.status.as_str(),
        "finished detox session"
    );

    Ok((
        StatusCode::OK,
        Json(FinishSessionResponse {
            id: updated.id,
            status: updated.status.as_str(),
            finished_at: updated.finished_at.unwrap_or(now),
        }),
    ))
}

fn detect_pro_field(
    theme_id: ThemeId,
    card_style: CardStyle,
    hide_watermark: bool,
    is_custom_message: bool,
    sanitized_message: Option<&str>,
) -> Option<&'static str> {
    if theme_id.is_pro() {
        return Some("theme_id");
    }
    if card_style.is_pro() {
        return Some("card_style");
    }
    if hide_watermark {
        return Some("hide_watermark");
    }
    if is_custom_message {
        return Some("is_custom_message");
    }
    if let Some(msg) = sanitized_message {
        if !is_preset_message(msg) {
            return Some("message");
        }
    }
    None
}

fn extract_bearer_token(headers: &HeaderMap) -> Result<&str, AppError> {
    let raw = headers
        .get(AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| AppError::unauthorized("Authorization Bearer トークンが必要です。"))?;

    let token = raw
        .strip_prefix("Bearer ")
        .or_else(|| raw.strip_prefix("bearer "))
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .ok_or_else(|| AppError::unauthorized("Authorization ヘッダ形式が不正です。"))?;

    Ok(token)
}
