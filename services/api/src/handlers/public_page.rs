use askama::Template;
use axum::extract::{Path, State};
use axum::http::header::CACHE_CONTROL;
use axum::http::{HeaderValue, StatusCode};
use axum::response::{Html, IntoResponse, Response};

use crate::domain::session::{
    current_unix_seconds, format_finished_time_label, format_remaining_ja,
    format_return_time_label, SessionStatus,
};
use crate::domain::token::is_valid_session_id;
use crate::error::AppError;
use crate::middleware::security_headers::apply_public_html_headers;
use crate::state::AppState;

#[derive(Template)]
#[template(path = "absence.html")]
struct AbsencePageTemplate {
    page_title: String,
    og_title: String,
    og_description: String,
    share_url: String,
    ogp_image_url: String,
    card_bg: &'static str,
    card_border: &'static str,
    card_primary: &'static str,
    card_secondary: &'static str,
    card_seal: &'static str,
    status_class: &'static str,
    status_badge: &'static str,
    headline_text: String,
    is_active: bool,
    is_completed: bool,
    return_time_label: String,
    remaining_label: String,
    finished_time_label: String,
    message: Option<String>,
    theme_label: &'static str,
    hide_watermark: bool,
    app_store_url: String,
    report_url: Option<String>,
}

#[derive(Template)]
#[template(path = "gone.html")]
struct GonePageTemplate {
    app_store_url: String,
}

#[derive(Template)]
#[template(path = "not_found.html")]
struct NotFoundPageTemplate {
    app_store_url: String,
}

#[derive(Template)]
#[template(path = "legal_privacy.html")]
struct LegalPrivacyTemplate {
    support_form_url: String,
}

#[derive(Template)]
#[template(path = "legal_terms.html")]
struct LegalTermsTemplate {
    support_form_url: String,
}

/// `GET /s/{id}`
pub async fn absence_page(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Response, AppError> {
    if !is_valid_session_id(&id) {
        return render_not_found_html(&state.app_store_url);
    }

    let Some(session) = state.repo.find_by_id(&id).await? else {
        return render_not_found_html(&state.app_store_url);
    };

    if !session.is_public {
        return render_not_found_html(&state.app_store_url);
    }

    let now = current_unix_seconds();
    if session.is_expired(now) {
        return render_gone_html(&state.app_store_url);
    }

    let tz = session.parsed_timezone();
    let palette = session.card_style.palette();
    let return_time_label = format_return_time_label(session.ends_at, tz);
    let remaining_label = format_remaining_ja(session.ends_at, now);
    let finished_ts = session.finished_at.unwrap_or(session.ends_at);
    let finished_time_label = format_finished_time_label(finished_ts, tz);
    let effective_status = session.effective_public_status(now);

    let (status_class, status_badge, is_active, is_completed, headline_text, page_title) =
        match effective_status {
            SessionStatus::Active => {
                let headline = match session.display_name.as_deref() {
                    Some(name) => format!("{name} さんは、ただいま雲隠れ中です"),
                    None => "ただいま、雲隠れしています".to_string(),
                };
                let title = match session.display_name.as_deref() {
                    Some(name) => format!("{name}さんはただいま雲隠れ中です | 雲隠れ"),
                    None => "ただいま雲隠れ中です | 雲隠れ".to_string(),
                };
                ("active", "雲隠れ中", true, false, headline, title)
            }
            SessionStatus::Completed => {
                let headline = match session.display_name.as_deref() {
                    Some(name) => format!("{name} さんは、雲隠れから帰還しました"),
                    None => "雲隠れから帰還しました".to_string(),
                };
                let title = match session.display_name.as_deref() {
                    Some(name) => format!("{name}さんは雲隠れから帰還しました | 雲隠れ"),
                    None => "雲隠れから帰還しました | 雲隠れ".to_string(),
                };
                ("completed", "帰還済み", false, true, headline, title)
            }
            SessionStatus::Canceled => {
                let headline = match session.display_name.as_deref() {
                    Some(name) => format!("{name} さんは、ひと足早く雲の中から戻りました"),
                    None => "予定より少し早く雲の中から戻りました".to_string(),
                };
                let title = match session.display_name.as_deref() {
                    Some(name) => format!("{name}さんはひと足早く帰還しました | 雲隠れ"),
                    None => "ひと足早く帰還しました | 雲隠れ".to_string(),
                };
                ("canceled", "ひと足早く帰還", false, false, headline, title)
            }
        };

    let og_title = match session.display_name.as_deref() {
        Some(name) => format!("{name} さんはただいま雲隠れ中です"),
        None => "ただいま、雲隠れ中です".to_string(),
    };
    let og_description = match session.message.as_deref() {
        Some(msg) => format!("帰還予定：{return_time_label}。「{msg}」"),
        None => format!("帰還予定：{return_time_label}。"),
    };

    let report_url = state
        .report_form_url_template
        .as_ref()
        .map(|tpl| tpl.replace("{session_id}", &session.id));

    let html = AbsencePageTemplate {
        page_title,
        og_title,
        og_description,
        share_url: format!("{}/s/{}", state.base_url, session.id),
        ogp_image_url: format!("{}/ogp/{}.png", state.base_url, session.id),
        card_bg: palette.bg,
        card_border: palette.border,
        card_primary: palette.primary,
        card_secondary: palette.secondary,
        card_seal: palette.seal,
        status_class,
        status_badge,
        headline_text,
        is_active,
        is_completed,
        return_time_label,
        remaining_label,
        finished_time_label,
        message: session.message,
        theme_label: session.theme_id.label_ja(),
        hide_watermark: session.hide_watermark,
        app_store_url: state.app_store_url.clone(),
        report_url,
    }
    .render()?;

    let mut res = (StatusCode::OK, Html(html)).into_response();
    res.headers_mut().insert(
        CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=30, s-maxage=30"),
    );
    apply_public_html_headers(&mut res);
    Ok(res)
}

/// `GET /legal/privacy`
pub async fn legal_privacy(State(state): State<AppState>) -> Result<Response, AppError> {
    let html = LegalPrivacyTemplate {
        support_form_url: state.support_form_url.clone(),
    }
    .render()?;

    let mut res = (StatusCode::OK, Html(html)).into_response();
    res.headers_mut().insert(
        CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=3600, s-maxage=3600"),
    );
    apply_public_html_headers(&mut res);
    Ok(res)
}

/// `GET /legal/terms`
pub async fn legal_terms(State(state): State<AppState>) -> Result<Response, AppError> {
    let html = LegalTermsTemplate {
        support_form_url: state.support_form_url.clone(),
    }
    .render()?;

    let mut res = (StatusCode::OK, Html(html)).into_response();
    res.headers_mut().insert(
        CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=3600, s-maxage=3600"),
    );
    apply_public_html_headers(&mut res);
    Ok(res)
}

fn render_not_found_html(app_store_url: &str) -> Result<Response, AppError> {
    let html = NotFoundPageTemplate {
        app_store_url: app_store_url.to_string(),
    }
    .render()?;

    let mut res = (StatusCode::NOT_FOUND, Html(html)).into_response();
    res.headers_mut()
        .insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
    apply_public_html_headers(&mut res);
    Ok(res)
}

fn render_gone_html(app_store_url: &str) -> Result<Response, AppError> {
    let html = GonePageTemplate {
        app_store_url: app_store_url.to_string(),
    }
    .render()?;

    let mut res = (StatusCode::GONE, Html(html)).into_response();
    res.headers_mut().insert(
        CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=3600"),
    );
    apply_public_html_headers(&mut res);
    Ok(res)
}
