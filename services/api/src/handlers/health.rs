use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct HealthQuery {
    pub deep: Option<String>,
}

#[derive(Debug, Serialize)]
struct HealthOkResponse<'a> {
    status: &'a str,
    db: &'a str,
    version: &'a str,
}

#[derive(Debug, Serialize)]
struct HealthDegradedResponse<'a> {
    status: &'a str,
    db: &'a str,
}

/// `GET /health` (with optional `?deep=1` database connectivity probe).
pub async fn health(State(state): State<AppState>, Query(query): Query<HealthQuery>) -> Response {
    let is_deep = matches!(query.deep.as_deref(), Some("1") | Some("true"));

    if is_deep {
        if let Err(err) = probe_database(&state).await {
            tracing::error!(error = %err, "deep healthcheck database probe failed");
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(HealthDegradedResponse {
                    status: "degraded",
                    db: "error",
                }),
            )
                .into_response();
        }
    }

    (
        StatusCode::OK,
        Json(HealthOkResponse {
            status: "ok",
            db: "ok",
            version: state.version,
        }),
    )
        .into_response()
}

async fn probe_database(state: &AppState) -> Result<(), libsql::Error> {
    let conn = state.db.connect()?;
    let mut rows = conn.query("SELECT 1", ()).await?;
    let _ = rows.next().await?;
    Ok(())
}
