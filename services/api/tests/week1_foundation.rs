use std::path::Path;
use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use kumogakure_api::build_router;
use kumogakure_api::state::{load_fonts, open_database, AppState};
use serde_json::Value;
use tower::ServiceExt;

async fn test_app() -> axum::Router {
    let db = open_database(":memory:", None)
        .await
        .expect("in-memory libsql should open");
    let fonts = load_fonts(Path::new("assets/fonts")).expect("bundled fonts should load");
    let state = AppState {
        db: Arc::new(db),
        fonts: Arc::new(fonts),
        app_env: "test".to_string(),
        base_url: "http://localhost:8080".to_string(),
        version: env!("CARGO_PKG_VERSION"),
    };
    build_router(state)
}

#[tokio::test]
async fn health_shallow_returns_ok() {
    let app = test_app().await;
    let response = app
        .oneshot(
            Request::builder()
                .uri("/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["status"], "ok");
    assert_eq!(json["db"], "ok");
    assert_eq!(json["version"], env!("CARGO_PKG_VERSION"));
}

#[tokio::test]
async fn health_deep_verifies_database_query() {
    let app = test_app().await;
    let response = app
        .oneshot(
            Request::builder()
                .uri("/health?deep=1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = response.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["status"], "ok");
    assert_eq!(json["db"], "ok");
}

#[tokio::test]
async fn migration_0001_init_is_idempotent_and_creates_expected_schema() {
    let db = open_database(":memory:", None)
        .await
        .expect("in-memory libsql should open");
    let conn = db.connect().expect("connection should succeed");
    let sql = include_str!("../migrations/0001_init.sql");

    // Execute twice to confirm idempotency
    conn.execute_batch(sql)
        .await
        .expect("first migration run should succeed");
    conn.execute_batch(sql)
        .await
        .expect("second migration run should succeed");

    let mut rows = conn
        .query(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'index') AND name IN ('sessions', '_schema_migrations', 'idx_sessions_active', 'idx_sessions_user_active', 'idx_sessions_expires_at') ORDER BY name",
            (),
        )
        .await
        .expect("sqlite_master query should succeed");

    let mut found = Vec::new();
    while let Some(row) = rows.next().await.unwrap() {
        found.push(row.get::<String>(0).unwrap());
    }

    assert_eq!(
        found,
        vec![
            "_schema_migrations",
            "idx_sessions_active",
            "idx_sessions_expires_at",
            "idx_sessions_user_active",
            "sessions",
        ]
    );

    let mut mig_rows = conn
        .query(
            "SELECT version FROM _schema_migrations WHERE version = '0001_init'",
            (),
        )
        .await
        .unwrap();
    assert!(mig_rows.next().await.unwrap().is_some());
}

#[test]
fn bundled_japanese_fonts_resolve_in_fontdb() {
    let fonts = load_fonts(Path::new("assets/fonts")).expect("bundled fonts should load");
    assert!(fonts.faces().count() >= 2);

    for family in ["Shippori Mincho", "Noto Serif JP"] {
        let id = fonts.query(&fontdb::Query {
            families: &[fontdb::Family::Name(family)],
            ..Default::default()
        });
        assert!(id.is_some(), "expected font family '{family}' to resolve");
    }
}
