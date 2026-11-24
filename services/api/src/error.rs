use axum::extract::rejection::JsonRejection;
use axum::extract::{FromRequest, Request};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;

/// Unified application error mapped to the JSON error envelope in `api-spec.md`.
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("invalid request: {message}")]
    InvalidRequest { message: String },

    #[error("validation error: {message}")]
    Validation {
        message: String,
        field: Option<&'static str>,
    },

    #[error("unauthorized: {message}")]
    Unauthorized { message: String },

    #[error("pro subscription required for field '{field}'")]
    ProRequired { field: &'static str },

    #[error("content policy violation on field '{field}': {message}")]
    ContentPolicyViolation {
        field: &'static str,
        message: String,
    },

    #[error("session not found")]
    SessionNotFound,

    #[error("session expired")]
    SessionExpired,

    #[error("rate limited")]
    RateLimited,

    #[error("internal error: {0}")]
    Internal(String),
}

#[derive(Debug, Serialize)]
struct ErrorEnvelope<'a> {
    error: ErrorBody<'a>,
}

#[derive(Debug, Serialize)]
struct ErrorBody<'a> {
    code: &'static str,
    message: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<ErrorDetails<'a>>,
}

#[derive(Debug, Serialize)]
struct ErrorDetails<'a> {
    field: &'a str,
}

impl AppError {
    pub fn validation(field: &'static str, message: impl Into<String>) -> Self {
        Self::Validation {
            message: message.into(),
            field: Some(field),
        }
    }

    pub fn invalid_request(message: impl Into<String>) -> Self {
        Self::InvalidRequest {
            message: message.into(),
        }
    }

    pub fn unauthorized(message: impl Into<String>) -> Self {
        Self::Unauthorized {
            message: message.into(),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        match self {
            Self::InvalidRequest { message } => (
                StatusCode::BAD_REQUEST,
                Json(ErrorEnvelope {
                    error: ErrorBody {
                        code: "INVALID_REQUEST",
                        message: &message,
                        details: None,
                    },
                }),
            )
                .into_response(),
            Self::Validation { message, field } => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(ErrorEnvelope {
                    error: ErrorBody {
                        code: "VALIDATION_ERROR",
                        message: &message,
                        details: field.map(|f| ErrorDetails { field: f }),
                    },
                }),
            )
                .into_response(),
            Self::Unauthorized { message } => (
                StatusCode::UNAUTHORIZED,
                Json(ErrorEnvelope {
                    error: ErrorBody {
                        code: "UNAUTHORIZED",
                        message: &message,
                        details: None,
                    },
                }),
            )
                .into_response(),
            Self::ProRequired { field } => (
                StatusCode::FORBIDDEN,
                Json(ErrorEnvelope {
                    error: ErrorBody {
                        code: "PRO_REQUIRED",
                        message: "この機能を利用するには隠者プラン（Pro）が必要です。",
                        details: Some(ErrorDetails { field }),
                    },
                }),
            )
                .into_response(),
            Self::ContentPolicyViolation { field, message } => (
                StatusCode::FORBIDDEN,
                Json(ErrorEnvelope {
                    error: ErrorBody {
                        code: "CONTENT_POLICY_VIOLATION",
                        message: &message,
                        details: Some(ErrorDetails { field }),
                    },
                }),
            )
                .into_response(),
            Self::SessionNotFound => (
                StatusCode::NOT_FOUND,
                Json(ErrorEnvelope {
                    error: ErrorBody {
                        code: "SESSION_NOT_FOUND",
                        message: "指定されたセッションが見つかりません。",
                        details: None,
                    },
                }),
            )
                .into_response(),
            Self::SessionExpired => (
                StatusCode::GONE,
                Json(ErrorEnvelope {
                    error: ErrorBody {
                        code: "SESSION_EXPIRED",
                        message: "この不在証明は有効期限切れです。",
                        details: None,
                    },
                }),
            )
                .into_response(),
            Self::RateLimited => (
                StatusCode::TOO_MANY_REQUESTS,
                Json(ErrorEnvelope {
                    error: ErrorBody {
                        code: "RATE_LIMITED",
                        message: "リクエストが集中しています。しばらくしてからお試しください。",
                        details: None,
                    },
                }),
            )
                .into_response(),
            Self::Internal(detail) => {
                tracing::error!(error = %detail, "internal server error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorEnvelope {
                        error: ErrorBody {
                            code: "INTERNAL_ERROR",
                            message: "サーバー内部エラーが発生しました。",
                            details: None,
                        },
                    }),
                )
                    .into_response()
            }
        }
    }
}

impl From<libsql::Error> for AppError {
    fn from(err: libsql::Error) -> Self {
        Self::Internal(format!("database error: {err}"))
    }
}

impl From<askama::Error> for AppError {
    fn from(err: askama::Error) -> Self {
        Self::Internal(format!("template error: {err}"))
    }
}

/// JSON extractor converting Axum `JsonRejection` into `400 INVALID_REQUEST` JSON.
pub struct AppJson<T>(pub T);

impl<S, T> FromRequest<S> for AppJson<T>
where
    axum::Json<T>: FromRequest<S, Rejection = JsonRejection>,
    S: Send + Sync,
{
    type Rejection = AppError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        match axum::Json::<T>::from_request(req, state).await {
            Ok(axum::Json(value)) => Ok(Self(value)),
            Err(rejection) => {
                tracing::debug!(status = %rejection.status(), "invalid JSON request body");
                Err(AppError::invalid_request(format!(
                    "リクエストJSONが不正です: {}",
                    rejection.body_text()
                )))
            }
        }
    }
}
