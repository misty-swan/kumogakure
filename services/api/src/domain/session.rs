use chrono::{DateTime, TimeZone, Utc};
use chrono_tz::Tz;
use uuid::{Uuid, Version};

use crate::domain::catalog::{CardStyle, ThemeId};
use crate::error::AppError;

pub const MIN_DURATION_MINUTES: i64 = 15;
pub const MAX_DURATION_MINUTES: i64 = 720;
pub const SESSION_TTL_SECONDS: i64 = 86_400;
pub const CLEANUP_GRACE_SECONDS: i64 = 86_400;

/// Session lifecycle status persisted in Turso (`database-design.md` §1.2).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionStatus {
    Active,
    Completed,
    Canceled,
}

impl SessionStatus {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Completed => "completed",
            Self::Canceled => "canceled",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "active" => Some(Self::Active),
            "completed" => Some(Self::Completed),
            "canceled" => Some(Self::Canceled),
            _ => None,
        }
    }
}

/// Complete domain record representing a row in `sessions`.
#[derive(Debug, Clone)]
pub struct SessionRecord {
    pub id: String,
    pub user_uuid: String,
    pub owner_token_hash: String,
    pub display_name: Option<String>,
    pub message: Option<String>,
    pub theme_id: ThemeId,
    pub card_style: CardStyle,
    pub hide_watermark: bool,
    pub is_public: bool,
    pub timezone: String,
    pub status: SessionStatus,
    pub started_at: i64,
    pub ends_at: i64,
    pub finished_at: Option<i64>,
    pub expires_at: i64,
}

impl SessionRecord {
    pub fn parsed_timezone(&self) -> Tz {
        self.timezone
            .parse::<Tz>()
            .unwrap_or(chrono_tz::Asia::Tokyo)
    }

    pub fn is_expired(&self, now: i64) -> bool {
        self.expires_at <= now
    }

    /// Effective status shown on `/s/{id}`: once `ends_at` has passed without explicit `/finish`,
    /// treat an `active` session as returned.
    pub fn effective_public_status(&self, now: i64) -> SessionStatus {
        match self.status {
            SessionStatus::Active if self.ends_at <= now => SessionStatus::Completed,
            other => other,
        }
    }
}

/// Validate UUID v4 and normalize to lowercase hyphenated representation.
pub fn validate_user_uuid(raw: &str) -> Result<String, AppError> {
    let trimmed = raw.trim();
    let parsed = Uuid::parse_str(trimmed).map_err(|_| {
        AppError::validation(
            "user_uuid",
            "user_uuid は有効な UUID v4 である必要があります。",
        )
    })?;

    if parsed.get_version() != Some(Version::Random) {
        return Err(AppError::validation(
            "user_uuid",
            "user_uuid は UUID v4 である必要があります。",
        ));
    }

    Ok(parsed.hyphenated().to_string())
}

/// Validate `duration_minutes` against MVP bounds (`15..=720`).
pub fn validate_duration_minutes(minutes: i64) -> Result<i64, AppError> {
    if !(MIN_DURATION_MINUTES..=MAX_DURATION_MINUTES).contains(&minutes) {
        return Err(AppError::validation(
            "duration_minutes",
            format!(
                "duration_minutes は {MIN_DURATION_MINUTES}〜{MAX_DURATION_MINUTES} 分の範囲で指定してください。"
            ),
        ));
    }
    Ok(minutes)
}

/// Parse an optional IANA timezone name (`chrono-tz`), defaulting to `Asia/Tokyo`.
pub fn parse_timezone(raw: Option<&str>) -> Result<Tz, AppError> {
    match raw {
        None => Ok(chrono_tz::Asia::Tokyo),
        Some(s) => {
            let trimmed = s.trim();
            if trimmed.is_empty() {
                return Err(AppError::validation(
                    "timezone",
                    "有効な IANA タイムゾーン名を指定してください。",
                ));
            }
            trimmed.parse::<Tz>().map_err(|_| {
                AppError::validation("timezone", "有効な IANA タイムゾーン名を指定してください。")
            })
        }
    }
}

/// Return current UTC UNIX seconds.
pub fn current_unix_seconds() -> i64 {
    Utc::now().timestamp()
}

fn to_tz_datetime(unix_seconds: i64, tz: Tz) -> DateTime<Tz> {
    let utc = Utc
        .timestamp_opt(unix_seconds, 0)
        .single()
        .unwrap_or_else(Utc::now);
    utc.with_timezone(&tz)
}

/// Format UNIX seconds in `tz` as `HH:MM`.
pub fn format_hhmm(unix_seconds: i64, tz: Tz) -> String {
    to_tz_datetime(unix_seconds, tz).format("%H:%M").to_string()
}

/// Compute a concise timezone indicator (e.g. `JST`, `EST`, or `UTC+09:00`).
pub fn tz_short_label(unix_seconds: i64, tz: Tz) -> String {
    if tz == chrono_tz::Asia::Tokyo {
        return "JST".to_string();
    }

    let dt = to_tz_datetime(unix_seconds, tz);
    let abbr = dt.format("%Z").to_string();
    if !abbr.is_empty() && abbr.chars().all(|c| c.is_ascii_alphabetic()) {
        abbr
    } else {
        format!("UTC{}", dt.format("%:z"))
    }
}

/// Format planned return time for OGP and `/s/{id}`, e.g. `21:30 頃 (JST)`.
pub fn format_return_time_label(unix_seconds: i64, tz: Tz) -> String {
    let hhmm = format_hhmm(unix_seconds, tz);
    let label = tz_short_label(unix_seconds, tz);
    format!("{hhmm} 頃 ({label})")
}

/// Format completion timestamp for `/s/{id}`, e.g. `21:30 (JST)`.
pub fn format_finished_time_label(unix_seconds: i64, tz: Tz) -> String {
    let hhmm = format_hhmm(unix_seconds, tz);
    let label = tz_short_label(unix_seconds, tz);
    format!("{hhmm} ({label})")
}

/// Format remaining duration in calm Japanese phrasing.
pub fn format_remaining_ja(ends_at: i64, now: i64) -> String {
    let diff = (ends_at - now).max(0);
    if diff == 0 {
        return "まもなく帰還".to_string();
    }
    let total_minutes = (diff + 59) / 60;
    let hours = total_minutes / 60;
    let mins = total_minutes % 60;
    if hours == 0 {
        format!("残り約 {total_minutes} 分")
    } else if mins == 0 {
        format!("残り約 {hours} 時間")
    } else {
        format!("残り約 {hours} 時間 {mins} 分")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uuid_v4_validation_rejects_v1_and_invalid_strings() {
        let valid = "550E8400-E29B-41D4-A716-446655440000";
        assert_eq!(
            validate_user_uuid(valid).unwrap(),
            "550e8400-e29b-41d4-a716-446655440000"
        );

        // v1 UUID must be rejected
        let v1 = "6ba7b810-9dad-11d1-80b4-00c04fd430c8";
        assert!(matches!(
            validate_user_uuid(v1),
            Err(AppError::Validation {
                field: Some("user_uuid"),
                ..
            })
        ));

        assert!(validate_user_uuid("not-a-uuid").is_err());
    }

    #[test]
    fn timezone_conversion_handles_tokyo_and_new_york() {
        assert_eq!(parse_timezone(None).unwrap(), chrono_tz::Asia::Tokyo);
        assert!(parse_timezone(Some("Mars/Olympus")).is_err());

        // 2026-01-15T12:30:00Z -> 21:30 JST / 07:30 EST
        let ts = 1_768_480_200;
        assert_eq!(
            format_return_time_label(ts, chrono_tz::Asia::Tokyo),
            "21:30 頃 (JST)"
        );
        let ny = parse_timezone(Some("America/New_York")).unwrap();
        assert_eq!(format_return_time_label(ts, ny), "07:30 頃 (EST)");
    }

    #[test]
    fn ttl_expiration_boundary_and_remaining_formatting() {
        let record = SessionRecord {
            id: "k9x2m7p4q8".to_string(),
            user_uuid: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            owner_token_hash: "00".repeat(32),
            display_name: None,
            message: None,
            theme_id: ThemeId::MistyMountain,
            card_style: CardStyle::WashiClassic,
            hide_watermark: false,
            is_public: true,
            timezone: "Asia/Tokyo".to_string(),
            status: SessionStatus::Active,
            started_at: 1_700_000_000,
            ends_at: 1_700_007_200,
            finished_at: None,
            expires_at: 1_700_086_400,
        };

        assert!(!record.is_expired(1_700_086_399));
        assert!(record.is_expired(1_700_086_400));
        assert_eq!(
            record.effective_public_status(1_700_007_199),
            SessionStatus::Active
        );
        assert_eq!(
            record.effective_public_status(1_700_007_200),
            SessionStatus::Completed
        );

        assert_eq!(
            format_remaining_ja(1_700_007_200, 1_700_000_000),
            "残り約 2 時間"
        );
        assert_eq!(
            format_remaining_ja(1_700_001_500, 1_700_000_000),
            "残り約 25 分"
        );
    }
}
