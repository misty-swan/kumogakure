use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Path as AxumPath, State as AxumState};
use axum::http::header::{AUTHORIZATION, CACHE_CONTROL, CONTENT_SECURITY_POLICY, CONTENT_TYPE};
use axum::http::{Request, StatusCode};
use axum::routing::get;
use axum::{Json, Router};
use chrono::Utc;
use http_body_util::BodyExt;
use kumogakure_api::build_router;
use kumogakure_api::domain::token::hash_owner_token;
use kumogakure_api::infra::revenuecat::RevenueCatClient;
use kumogakure_api::state::{load_fonts, open_database, AppState};
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tower::ServiceExt;

const MIGRATION_SQL: &str = include_str!("../migrations/0001_init.sql");

async fn setup_test_state() -> AppState {
    let db = open_database(":memory:", None)
        .await
        .expect("in-memory libsql should open");
    let fonts = load_fonts(Path::new("assets/fonts")).expect("fonts should load");
    let state = AppState::for_testing(db, fonts);
    let conn = state.repo.connect().expect("connection should succeed");
    conn.execute_batch(MIGRATION_SQL)
        .await
        .expect("migration should succeed");
    state
}

async fn response_json(res: axum::response::Response) -> Value {
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

async fn response_text(res: axum::response::Response) -> String {
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    String::from_utf8(bytes.to_vec()).unwrap()
}

async fn response_bytes(res: axum::response::Response) -> Vec<u8> {
    res.into_body().collect().await.unwrap().to_bytes().to_vec()
}

fn json_post(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header(CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

#[derive(Clone)]
struct MockRcState {
    calls: Arc<AtomicUsize>,
    mode: Arc<tokio::sync::RwLock<MockRcMode>>,
}

#[derive(Clone)]
enum MockRcMode {
    ActivePro,
    Inactive,
    NotFound,
    Expired,
    ServerError,
}

async fn mock_rc_handler(
    AxumState(state): AxumState<MockRcState>,
    AxumPath(_user_id): AxumPath<String>,
) -> (StatusCode, Json<Value>) {
    state.calls.fetch_add(1, Ordering::SeqCst);
    let mode = state.mode.read().await.clone();
    match mode {
        MockRcMode::ActivePro => (
            StatusCode::OK,
            Json(json!({
                "subscriber": {
                    "entitlements": {
                        "hermit_pro": {
                            "expires_date": "2099-01-01T00:00:00Z"
                        }
                    }
                }
            })),
        ),
        MockRcMode::Inactive => (
            StatusCode::OK,
            Json(json!({
                "subscriber": {
                    "entitlements": {}
                }
            })),
        ),
        MockRcMode::Expired => (
            StatusCode::OK,
            Json(json!({
                "subscriber": {
                    "entitlements": {
                        "hermit_pro": {
                            "expires_date": "2020-01-01T00:00:00Z"
                        }
                    }
                }
            })),
        ),
        MockRcMode::NotFound => (
            StatusCode::NOT_FOUND,
            Json(json!({ "message": "not found" })),
        ),
        MockRcMode::ServerError => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "message": "upstream failure" })),
        ),
    }
}

async fn spawn_mock_rc(initial_mode: MockRcMode) -> (String, MockRcState) {
    let state = MockRcState {
        calls: Arc::new(AtomicUsize::new(0)),
        mode: Arc::new(tokio::sync::RwLock::new(initial_mode)),
    };
    let app = Router::new()
        .route("/v1/subscribers/{user_id}", get(mock_rc_handler))
        .with_state(state.clone());

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    (format!("http://{addr}"), state)
}

#[tokio::test]
async fn public_session_flow_serves_escaped_html_and_1200x630_ogp_png() {
    let state = setup_test_state().await;
    let app = build_router(state.clone());

    let create_req = json_post(
        "/api/v1/sessions",
        json!({
            "user_uuid": "550e8400-e29b-41d4-a716-446655440000",
            "duration_minutes": 90,
            "theme_id": "misty_mountain",
            "card_style": "washi_classic",
            "hide_watermark": false,
            "is_public": true,
            "is_custom_message": false,
            "display_name": "<script>x</script>",
            "message": "読書してきます",
            "timezone": "Asia/Tokyo"
        }),
    );

    let res = app.clone().oneshot(create_req).await.unwrap();
    assert_eq!(res.status(), StatusCode::CREATED);
    let created = response_json(res).await;

    let id = created["id"].as_str().unwrap().to_string();
    let owner_token = created["owner_token"].as_str().unwrap().to_string();
    assert_eq!(id.len(), 10);
    assert_eq!(owner_token.len(), 64);
    assert_eq!(created["status"], "active");
    assert_eq!(
        created["expires_at"].as_i64().unwrap(),
        created["started_at"].as_i64().unwrap() + 86_400
    );
    assert_eq!(
        created["share_url"].as_str().unwrap(),
        format!("http://localhost:8080/s/{id}")
    );
    assert_eq!(
        created["ogp_image_url"].as_str().unwrap(),
        format!("http://localhost:8080/ogp/{id}.png")
    );

    // Verify DB stores hashed token instead of plaintext token
    let stored = state.repo.find_by_id(&id).await.unwrap().unwrap();
    assert_ne!(stored.owner_token_hash, owner_token);
    assert_eq!(stored.owner_token_hash, hash_owner_token(&owner_token));

    // GET /s/{id}
    let html_res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/s/{id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(html_res.status(), StatusCode::OK);
    assert_eq!(
        html_res.headers().get("x-robots-tag").unwrap(),
        "noindex, nofollow"
    );
    assert_eq!(
        html_res.headers().get(CACHE_CONTROL).unwrap(),
        "public, max-age=30, s-maxage=30"
    );
    let csp = html_res
        .headers()
        .get(CONTENT_SECURITY_POLICY)
        .unwrap()
        .to_str()
        .unwrap();
    assert!(csp.contains("frame-ancestors 'none'"));
    assert!(csp.contains("object-src 'none'"));

    let html = response_text(html_res).await;
    assert!(html.contains(r#"<meta name="robots" content="noindex, nofollow">"#));
    assert!(html.contains(&format!("http://localhost:8080/ogp/{id}.png")));
    assert!(html.contains("&lt;script&gt;x&lt;/script&gt;"));
    assert!(!html.contains("<script>x</script>"));
    assert!(html.contains(&format!("entry.1371370885={id}")));
    assert!(html.contains("雲隠れ - Kumogakure"));

    // GET /ogp/{id}.png
    let ogp_res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/ogp/{id}.png"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(ogp_res.status(), StatusCode::OK);
    assert_eq!(ogp_res.headers().get(CONTENT_TYPE).unwrap(), "image/png");
    assert_eq!(
        ogp_res.headers().get(CACHE_CONTROL).unwrap(),
        "public, max-age=86400, s-maxage=86400, immutable"
    );
    assert_eq!(
        ogp_res.headers().get("x-robots-tag").unwrap(),
        "noindex, nofollow"
    );

    let png_bytes = response_bytes(ogp_res).await;
    assert!(png_bytes.starts_with(b"\x89PNG\r\n\x1a\n"));
    let decoder = png::Decoder::new(png_bytes.as_slice());
    let reader = decoder.read_info().unwrap();
    assert_eq!(reader.info().width, 1200);
    assert_eq!(reader.info().height, 630);
}

#[tokio::test]
async fn private_session_returns_404_on_public_routes_and_counts_in_stats() {
    let state = setup_test_state().await;
    let app = build_router(state);

    let res = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440001",
                "duration_minutes": 30,
                "theme_id": "rainy_bamboo",
                "is_public": false
            }),
        ))
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::CREATED);
    let created = response_json(res).await;
    assert!(created["share_url"].is_null());
    assert!(created["ogp_image_url"].is_null());
    let id = created["id"].as_str().unwrap();

    // Private session must return 404 on both /s/{id} and /ogp/{id}.png
    let page_res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/s/{id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(page_res.status(), StatusCode::NOT_FOUND);
    assert_eq!(page_res.headers().get(CACHE_CONTROL).unwrap(), "no-store");
    assert_eq!(
        page_res.headers().get("x-robots-tag").unwrap(),
        "noindex, nofollow"
    );

    let ogp_res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/ogp/{id}.png"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(ogp_res.status(), StatusCode::NOT_FOUND);
    assert_eq!(ogp_res.headers().get(CACHE_CONTROL).unwrap(), "no-store");

    // Non-.png and invalid IDs also return 404
    let bad_ogp = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/ogp/{id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(bad_ogp.status(), StatusCode::NOT_FOUND);

    // Active count includes private sessions
    let stats_res = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/stats/active")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(stats_res.status(), StatusCode::OK);
    assert_eq!(
        stats_res.headers().get(CACHE_CONTROL).unwrap(),
        "public, max-age=30, s-maxage=30"
    );
    let stats = response_json(stats_res).await;
    assert_eq!(stats["active_count"], 1);
}

#[tokio::test]
async fn creating_new_session_cancels_previous_active_for_same_user() {
    let state = setup_test_state().await;
    let app = build_router(state.clone());
    let user_uuid = "550e8400-e29b-41d4-a716-446655440002";

    let res1 = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": user_uuid,
                "duration_minutes": 30,
                "theme_id": "misty_mountain",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    let first = response_json(res1).await;
    let first_id = first["id"].as_str().unwrap();

    let res2 = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": user_uuid,
                "duration_minutes": 45,
                "theme_id": "rainy_bamboo",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(res2.status(), StatusCode::CREATED);

    let first_row = state.repo.find_by_id(first_id).await.unwrap().unwrap();
    assert_eq!(first_row.status.as_str(), "canceled");
    assert!(first_row.finished_at.is_some());

    let stats_res = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/stats/active")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let stats = response_json(stats_res).await;
    assert_eq!(stats["active_count"], 1);
}

#[tokio::test]
async fn finish_session_enforces_token_and_is_idempotent() {
    let state = setup_test_state().await;
    let app = build_router(state);

    let create_res = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440003",
                "duration_minutes": 60,
                "theme_id": "misty_mountain",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    let created = response_json(create_res).await;
    let id = created["id"].as_str().unwrap();
    let token = created["owner_token"].as_str().unwrap();

    // Missing auth header -> 401
    let no_auth = app
        .clone()
        .oneshot(json_post(
            &format!("/api/v1/sessions/{id}/finish"),
            json!({ "outcome": "completed" }),
        ))
        .await
        .unwrap();
    assert_eq!(no_auth.status(), StatusCode::UNAUTHORIZED);

    // Wrong token -> 401
    let wrong_auth = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/sessions/{id}/finish"))
                .header(CONTENT_TYPE, "application/json")
                .header(AUTHORIZATION, "Bearer wrong-token")
                .body(Body::from(json!({ "outcome": "completed" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(wrong_auth.status(), StatusCode::UNAUTHORIZED);

    // Valid token -> 200 completed
    let ok_finish = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/sessions/{id}/finish"))
                .header(CONTENT_TYPE, "application/json")
                .header(AUTHORIZATION, format!("Bearer {token}"))
                .body(Body::from(json!({ "outcome": "completed" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(ok_finish.status(), StatusCode::OK);
    let body1 = response_json(ok_finish).await;
    assert_eq!(body1["status"], "completed");

    // Second finish with different outcome -> 200 idempotent, still completed
    let retry_finish = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/sessions/{id}/finish"))
                .header(CONTENT_TYPE, "application/json")
                .header(AUTHORIZATION, format!("Bearer {token}"))
                .body(Body::from(json!({ "outcome": "canceled" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(retry_finish.status(), StatusCode::OK);
    let body2 = response_json(retry_finish).await;
    assert_eq!(body2["status"], "completed");
    assert_eq!(body2["finished_at"], body1["finished_at"]);

    // /s/{id} reflects completed status
    let page = app
        .oneshot(
            Request::builder()
                .uri(format!("/s/{id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let html = response_text(page).await;
    assert!(html.contains("帰還済み"));
}

#[tokio::test]
async fn validation_and_content_policy_return_expected_error_envelopes() {
    let state = setup_test_state().await;
    let app = build_router(state);

    // Malformed JSON -> 400 INVALID_REQUEST
    let bad_json = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/sessions")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from("{invalid"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(bad_json.status(), StatusCode::BAD_REQUEST);
    assert_eq!(
        response_json(bad_json).await["error"]["code"],
        "INVALID_REQUEST"
    );

    // Out-of-range duration -> 422 VALIDATION_ERROR
    let bad_duration = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440004",
                "duration_minutes": 10,
                "theme_id": "misty_mountain",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(bad_duration.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let err = response_json(bad_duration).await;
    assert_eq!(err["error"]["code"], "VALIDATION_ERROR");
    assert_eq!(err["error"]["details"]["field"], "duration_minutes");

    // URL in display_name -> 403 CONTENT_POLICY_VIOLATION
    let url_name = app
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440004",
                "duration_minutes": 30,
                "theme_id": "misty_mountain",
                "is_public": true,
                "display_name": "https://spam.jp"
            }),
        ))
        .await
        .unwrap();
    assert_eq!(url_name.status(), StatusCode::FORBIDDEN);
    assert_eq!(
        response_json(url_name).await["error"]["code"],
        "CONTENT_POLICY_VIOLATION"
    );
}

#[tokio::test]
async fn revenuecat_verification_handles_pro_free_cache_and_fail_open() {
    let (rc_url, mock_rc) = spawn_mock_rc(MockRcMode::Inactive).await;
    let mut state = setup_test_state().await;
    state.revenuecat = Arc::new(RevenueCatClient::new(
        &rc_url,
        Some("sk_test_secret".to_string()),
        false,
    ));
    let app = build_router(state.clone());

    // 1) Free request should not invoke RevenueCat at all
    let free_res = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440010",
                "duration_minutes": 30,
                "theme_id": "misty_mountain",
                "is_public": true,
                "message": "読書してきます"
            }),
        ))
        .await
        .unwrap();
    assert_eq!(free_res.status(), StatusCode::CREATED);
    assert_eq!(mock_rc.calls.load(Ordering::SeqCst), 0);

    // 2) Unsubscribed user sending hide_watermark: true -> 403 PRO_REQUIRED
    let pro_denied = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440011",
                "duration_minutes": 30,
                "theme_id": "misty_mountain",
                "hide_watermark": true,
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(pro_denied.status(), StatusCode::FORBIDDEN);
    let err = response_json(pro_denied).await;
    assert_eq!(err["error"]["code"], "PRO_REQUIRED");
    assert_eq!(err["error"]["details"]["field"], "hide_watermark");
    assert_eq!(mock_rc.calls.load(Ordering::SeqCst), 1);

    // 3) Bypass attempt: custom message while is_custom_message: false -> 403 PRO_REQUIRED (uses cached false)
    let bypass = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440011",
                "duration_minutes": 30,
                "theme_id": "misty_mountain",
                "is_custom_message": false,
                "message": "プリセット以外の文言",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(bypass.status(), StatusCode::FORBIDDEN);
    assert_eq!(mock_rc.calls.load(Ordering::SeqCst), 1);

    // 4) Subscribed user -> 201 Created and second call hits 60s cache
    *mock_rc.mode.write().await = MockRcMode::ActivePro;
    let pro_ok_1 = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440012",
                "duration_minutes": 60,
                "theme_id": "moonlit_lake",
                "card_style": "sumi_night",
                "hide_watermark": true,
                "is_custom_message": true,
                "message": "静かな夜を過ごしています",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(pro_ok_1.status(), StatusCode::CREATED);
    assert_eq!(mock_rc.calls.load(Ordering::SeqCst), 2);

    let pro_ok_2 = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440012",
                "duration_minutes": 60,
                "theme_id": "dawn_shrine",
                "card_style": "indigo_mist",
                "hide_watermark": true,
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(pro_ok_2.status(), StatusCode::CREATED);
    assert_eq!(mock_rc.calls.load(Ordering::SeqCst), 2);

    // 5) Expired or 404 subscriber -> 403 PRO_REQUIRED
    *mock_rc.mode.write().await = MockRcMode::Expired;
    let expired_res = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440013",
                "duration_minutes": 30,
                "theme_id": "dawn_shrine",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(expired_res.status(), StatusCode::FORBIDDEN);

    *mock_rc.mode.write().await = MockRcMode::NotFound;
    let not_found_rc = app
        .clone()
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440014",
                "duration_minutes": 30,
                "theme_id": "dawn_shrine",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(not_found_rc.status(), StatusCode::FORBIDDEN);

    // 6) Upstream 5xx: fail_open=false -> 500, fail_open=true -> 201
    *mock_rc.mode.write().await = MockRcMode::ServerError;
    let fail_closed = app
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440015",
                "duration_minutes": 30,
                "theme_id": "dawn_shrine",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(fail_closed.status(), StatusCode::INTERNAL_SERVER_ERROR);

    let mut open_state = state;
    open_state.revenuecat = Arc::new(RevenueCatClient::new(
        &rc_url,
        Some("sk_test_secret".to_string()),
        true,
    ));
    let open_app = build_router(open_state);
    let fail_open = open_app
        .oneshot(json_post(
            "/api/v1/sessions",
            json!({
                "user_uuid": "550e8400-e29b-41d4-a716-446655440016",
                "duration_minutes": 30,
                "theme_id": "dawn_shrine",
                "is_public": true
            }),
        ))
        .await
        .unwrap();
    assert_eq!(fail_open.status(), StatusCode::CREATED);
}

#[tokio::test]
async fn expired_sessions_return_410_and_cleanup_purges_past_48h_only() {
    let state = setup_test_state().await;
    let conn = state.repo.connect().unwrap();
    let now = Utc::now().timestamp();

    // Session expired 60s ago (within 24h..48h window -> should return 410 and NOT be deleted)
    conn.execute(
        "INSERT INTO sessions (
            id, user_uuid, owner_token_hash, display_name, message,
            theme_id, card_style, hide_watermark, is_public, timezone,
            status, started_at, ends_at, finished_at, expires_at
        ) VALUES (?1, ?2, ?3, NULL, NULL, 'misty_mountain', 'washi_classic', 0, 1, 'Asia/Tokyo', 'completed', ?4, ?5, ?5, ?6)",
        libsql::params![
            "gone_recnt",
            "550e8400-e29b-41d4-a716-446655440020",
            "00".repeat(32),
            now - 86_460,
            now - 84_000,
            now - 60,
        ],
    )
    .await
    .unwrap();

    // Session expired > 24h ago (past 48h from creation -> should be physically deleted)
    conn.execute(
        "INSERT INTO sessions (
            id, user_uuid, owner_token_hash, display_name, message,
            theme_id, card_style, hide_watermark, is_public, timezone,
            status, started_at, ends_at, finished_at, expires_at
        ) VALUES (?1, ?2, ?3, NULL, NULL, 'misty_mountain', 'washi_classic', 0, 1, 'Asia/Tokyo', 'completed', ?4, ?5, ?5, ?6)",
        libsql::params![
            "purge_old1",
            "550e8400-e29b-41d4-a716-446655440021",
            "00".repeat(32),
            now - 200_000,
            now - 190_000,
            now - 90_000,
        ],
    )
    .await
    .unwrap();

    let app = build_router(state.clone());

    let gone_html = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/s/gone_recnt")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(gone_html.status(), StatusCode::GONE);
    assert_eq!(
        gone_html.headers().get(CACHE_CONTROL).unwrap(),
        "public, max-age=3600"
    );
    assert_eq!(
        gone_html.headers().get("x-robots-tag").unwrap(),
        "noindex, nofollow"
    );
    assert!(response_text(gone_html).await.contains("霧に溶けました"));

    let gone_ogp = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/ogp/gone_recnt.png")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(gone_ogp.status(), StatusCode::GONE);
    assert_eq!(gone_ogp.headers().get(CACHE_CONTROL).unwrap(), "no-store");

    // Unauthorized cleanup -> 401
    let bad_cleanup = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/internal/cleanup")
                .header("X-Internal-Secret", "wrong-secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(bad_cleanup.status(), StatusCode::UNAUTHORIZED);

    // Authorized cleanup -> deletes 1 old row and keeps recent 410 row
    let ok_cleanup = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/internal/cleanup")
                .header("X-Internal-Secret", "test-cleanup-secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(ok_cleanup.status(), StatusCode::OK);
    let body = response_json(ok_cleanup).await;
    assert_eq!(body["deleted_count"], 1);
    assert!(state.repo.find_by_id("gone_recnt").await.unwrap().is_some());
    assert!(state.repo.find_by_id("purge_old1").await.unwrap().is_none());
}

#[tokio::test]
async fn legal_pages_return_html_with_cache_and_security_headers() {
    let state = setup_test_state().await;
    let app = build_router(state);

    for (path, expected_heading) in [
        ("/legal/privacy", "プライバシーポリシー"),
        ("/legal/terms", "利用規約"),
    ] {
        let res = app
            .clone()
            .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        assert_eq!(
            res.headers().get(CACHE_CONTROL).unwrap(),
            "public, max-age=3600, s-maxage=3600"
        );
        assert_eq!(
            res.headers().get("x-robots-tag").unwrap(),
            "noindex, nofollow"
        );
        let html = response_text(res).await;
        assert!(html.contains(expected_heading));
        assert!(html.contains("docs.google.com/forms"));
    }
}
