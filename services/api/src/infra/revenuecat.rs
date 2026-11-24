use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use chrono::{DateTime, Utc};
use reqwest::StatusCode;
use serde::Deserialize;
use tokio::sync::RwLock;

use crate::error::AppError;

pub const HERMIT_PRO_ENTITLEMENT_ID: &str = "hermit_pro";
const CACHE_TTL: Duration = Duration::from_secs(60);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_CACHE_ENTRIES: usize = 4096;

#[derive(Debug, Clone)]
struct CachedEntitlement {
    is_pro: bool,
    cached_at: Instant,
}

#[derive(Debug, Deserialize)]
struct SubscriberResponse {
    subscriber: Option<SubscriberPayload>,
}

#[derive(Debug, Deserialize)]
struct SubscriberPayload {
    #[serde(default)]
    entitlements: HashMap<String, EntitlementPayload>,
}

#[derive(Debug, Deserialize)]
struct EntitlementPayload {
    expires_date: Option<String>,
}

/// RevenueCat REST API v1 client with 60s in-memory cache and configurable fail-open behavior.
#[derive(Clone)]
pub struct RevenueCatClient {
    http: reqwest::Client,
    base_url: String,
    secret_api_key: Option<String>,
    fail_open: bool,
    cache: Arc<RwLock<HashMap<String, CachedEntitlement>>>,
}

impl RevenueCatClient {
    pub fn new(
        base_url: impl Into<String>,
        secret_api_key: Option<String>,
        fail_open: bool,
    ) -> Self {
        let http = reqwest::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .build()
            .expect("reqwest client builder should succeed");

        Self {
            http,
            base_url: base_url.into().trim_end_matches('/').to_string(),
            secret_api_key,
            fail_open,
            cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Check whether `user_uuid` holds an active `hermit_pro` entitlement.
    pub async fn verify_hermit_pro(&self, user_uuid: &str) -> Result<bool, AppError> {
        if let Some(cached) = self.get_cached(user_uuid).await {
            return Ok(cached);
        }

        let Some(api_key) = self.secret_api_key.as_deref() else {
            tracing::warn!(
                fail_open = self.fail_open,
                "REVENUECAT_SECRET_API_KEY is not configured"
            );
            return self.handle_upstream_failure("RevenueCat API key is not configured");
        };

        let url = format!("{}/v1/subscribers/{}", self.base_url, user_uuid);
        let response = match self.http.get(&url).bearer_auth(api_key).send().await {
            Ok(resp) => resp,
            Err(err) => {
                tracing::warn!(
                    error = %err,
                    fail_open = self.fail_open,
                    "RevenueCat API request error"
                );
                return self.handle_upstream_failure("RevenueCat API request failed");
            }
        };

        let status = response.status();
        if status == StatusCode::NOT_FOUND {
            self.put_cached(user_uuid, false).await;
            return Ok(false);
        }

        if !status.is_success() {
            tracing::warn!(
                status = %status,
                fail_open = self.fail_open,
                "RevenueCat API returned non-success status"
            );
            return self.handle_upstream_failure("RevenueCat API returned error status");
        }

        let body: SubscriberResponse = match response.json().await {
            Ok(parsed) => parsed,
            Err(err) => {
                tracing::warn!(
                    error = %err,
                    fail_open = self.fail_open,
                    "failed to decode RevenueCat subscriber response"
                );
                return self.handle_upstream_failure("RevenueCat response parse failed");
            }
        };

        let now = Utc::now().timestamp();
        let is_pro = is_entitlement_active(&body, now);
        self.put_cached(user_uuid, is_pro).await;
        Ok(is_pro)
    }

    fn handle_upstream_failure(&self, reason: &str) -> Result<bool, AppError> {
        if self.fail_open {
            Ok(true)
        } else {
            Err(AppError::Internal(reason.to_string()))
        }
    }

    async fn get_cached(&self, user_uuid: &str) -> Option<bool> {
        let guard = self.cache.read().await;
        guard.get(user_uuid).and_then(|entry| {
            if entry.cached_at.elapsed() < CACHE_TTL {
                Some(entry.is_pro)
            } else {
                None
            }
        })
    }

    async fn put_cached(&self, user_uuid: &str, is_pro: bool) {
        let mut guard = self.cache.write().await;
        if guard.len() >= MAX_CACHE_ENTRIES {
            guard.retain(|_, entry| entry.cached_at.elapsed() < CACHE_TTL);
        }
        guard.insert(
            user_uuid.to_string(),
            CachedEntitlement {
                is_pro,
                cached_at: Instant::now(),
            },
        );
    }
}

fn is_entitlement_active(body: &SubscriberResponse, now_unix: i64) -> bool {
    let Some(subscriber) = &body.subscriber else {
        return false;
    };
    let Some(entitlement) = subscriber.entitlements.get(HERMIT_PRO_ENTITLEMENT_ID) else {
        return false;
    };
    match entitlement.expires_date.as_deref() {
        None => true,
        Some(raw) => match DateTime::parse_from_rfc3339(raw) {
            Ok(dt) => dt.timestamp() > now_unix,
            Err(err) => {
                tracing::warn!(error = %err, "invalid expires_date format from RevenueCat");
                false
            }
        },
    }
}
