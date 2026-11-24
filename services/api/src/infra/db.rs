use std::sync::Arc;

use libsql::{params, Row};

use crate::domain::catalog::{CardStyle, ThemeId};
use crate::domain::session::{SessionRecord, SessionStatus};
use crate::error::AppError;

/// Persistence repository backed by Turso / libSQL.
#[derive(Clone)]
pub struct SessionRepository {
    db: Arc<libsql::Database>,
    pinned_conn: Option<libsql::Connection>,
}

impl SessionRepository {
    pub fn new(db: Arc<libsql::Database>) -> Self {
        Self {
            db,
            pinned_conn: None,
        }
    }

    /// Create a repository pinned to a single connection (required for `:memory:` SQLite databases
    /// where each `Database::connect()` otherwise opens an isolated unnamed memory database).
    pub fn new_pinned(db: Arc<libsql::Database>) -> Result<Self, libsql::Error> {
        let conn = db.connect()?;
        Ok(Self {
            db,
            pinned_conn: Some(conn),
        })
    }

    pub fn connect(&self) -> Result<libsql::Connection, libsql::Error> {
        match &self.pinned_conn {
            Some(conn) => Ok(conn.clone()),
            None => self.db.connect(),
        }
    }

    pub fn database(&self) -> &Arc<libsql::Database> {
        &self.db
    }

    /// Lightweight database probe for `GET /health?deep=1`.
    pub async fn ping(&self) -> Result<(), libsql::Error> {
        let conn = self.connect()?;
        let mut rows = conn.query("SELECT 1", ()).await?;
        let _ = rows.next().await?;
        Ok(())
    }

    /// Atomically cancel any existing active session for the same `user_uuid` and insert the new session.
    pub async fn create_session(&self, record: &SessionRecord, now: i64) -> Result<(), AppError> {
        let conn = self.connect()?;
        let tx = conn.transaction().await?;

        tx.execute(
            "UPDATE sessions SET status = 'canceled', finished_at = ?1 WHERE user_uuid = ?2 AND status = 'active'",
            params![now, record.user_uuid.clone()],
        )
        .await?;

        tx.execute(
            "INSERT INTO sessions (
                id, user_uuid, owner_token_hash, display_name, message,
                theme_id, card_style, hide_watermark, is_public, timezone,
                status, started_at, ends_at, finished_at, expires_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)",
            params![
                record.id.clone(),
                record.user_uuid.clone(),
                record.owner_token_hash.clone(),
                record.display_name.clone(),
                record.message.clone(),
                record.theme_id.as_str(),
                record.card_style.as_str(),
                if record.hide_watermark { 1_i64 } else { 0_i64 },
                if record.is_public { 1_i64 } else { 0_i64 },
                record.timezone.clone(),
                record.status.as_str(),
                record.started_at,
                record.ends_at,
                record.finished_at,
                record.expires_at,
            ],
        )
        .await?;

        tx.commit().await?;
        Ok(())
    }

    /// Look up a single session by its 10-character nanoid.
    pub async fn find_by_id(&self, id: &str) -> Result<Option<SessionRecord>, AppError> {
        let conn = self.connect()?;
        let mut rows = conn
            .query(
                "SELECT id, user_uuid, owner_token_hash, display_name, message,
                        theme_id, card_style, hide_watermark, is_public, timezone,
                        status, started_at, ends_at, finished_at, expires_at
                 FROM sessions WHERE id = ?1 LIMIT 1",
                params![id.to_string()],
            )
            .await?;

        match rows.next().await? {
            Some(row) => Ok(Some(row_to_session(&row)?)),
            None => Ok(None),
        }
    }

    /// Transition an `active` session to `completed` or `canceled`, returning the latest stored state.
    pub async fn finish_session_if_active(
        &self,
        id: &str,
        target_status: SessionStatus,
        finished_at: i64,
    ) -> Result<Option<SessionRecord>, AppError> {
        let conn = self.connect()?;
        conn.execute(
            "UPDATE sessions SET status = ?1, finished_at = ?2 WHERE id = ?3 AND status = 'active'",
            params![target_status.as_str(), finished_at, id.to_string()],
        )
        .await?;

        self.find_by_id(id).await
    }

    /// Count currently active sessions whose planned end time is still in the future.
    pub async fn count_active(&self, now: i64) -> Result<i64, AppError> {
        let conn = self.connect()?;
        let mut rows = conn
            .query(
                "SELECT COUNT(*) FROM sessions WHERE status = 'active' AND ends_at > ?1",
                params![now],
            )
            .await?;

        if let Some(row) = rows.next().await? {
            Ok(row.get::<i64>(0)?)
        } else {
            Ok(0)
        }
    }

    /// Physically delete sessions whose `expires_at` is strictly older than `cutoff_unix`.
    pub async fn delete_expired_before(&self, cutoff_unix: i64) -> Result<u64, AppError> {
        let conn = self.connect()?;
        let deleted = conn
            .execute(
                "DELETE FROM sessions WHERE expires_at < ?1",
                params![cutoff_unix],
            )
            .await?;
        Ok(deleted)
    }
}

fn row_to_session(row: &Row) -> Result<SessionRecord, AppError> {
    let theme_raw: String = row.get(5)?;
    let theme_id = ThemeId::parse(&theme_raw)
        .ok_or_else(|| AppError::Internal(format!("invalid theme_id in db: {theme_raw}")))?;

    let card_style_raw: String = row.get(6)?;
    let card_style = CardStyle::parse(&card_style_raw)
        .ok_or_else(|| AppError::Internal(format!("invalid card_style in db: {card_style_raw}")))?;

    let status_raw: String = row.get(10)?;
    let status = SessionStatus::parse(&status_raw)
        .ok_or_else(|| AppError::Internal(format!("invalid status in db: {status_raw}")))?;

    Ok(SessionRecord {
        id: row.get(0)?,
        user_uuid: row.get(1)?,
        owner_token_hash: row.get(2)?,
        display_name: row.get(3)?,
        message: row.get(4)?,
        theme_id,
        card_style,
        hide_watermark: row.get::<i64>(7)? != 0,
        is_public: row.get::<i64>(8)? != 0,
        timezone: row.get(9)?,
        status,
        started_at: row.get(11)?,
        ends_at: row.get(12)?,
        finished_at: row.get(13)?,
        expires_at: row.get(14)?,
    })
}
