use axum::body::Body;
use axum::http::header::{CONTENT_SECURITY_POLICY, REFERRER_POLICY, X_CONTENT_TYPE_OPTIONS};
use axum::http::{HeaderName, HeaderValue, Request};
use axum::middleware::Next;
use axum::response::Response;

pub static X_ROBOTS_TAG: HeaderName = HeaderName::from_static("x-robots-tag");

pub const PUBLIC_HTML_CSP: &str = "default-src 'self'; img-src 'self' https:; style-src 'self' 'unsafe-inline'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'";
pub const NOINDEX_NOFOLLOW: &str = "noindex, nofollow";

/// Apply baseline security headers to every HTTP response.
pub async fn apply_baseline_security_headers(req: Request<Body>, next: Next) -> Response {
    let mut res = next.run(req).await;
    let headers = res.headers_mut();
    headers.insert(X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    headers.insert(REFERRER_POLICY, HeaderValue::from_static("no-referrer"));
    res
}

/// Attach `X-Robots-Tag: noindex, nofollow` and strict CSP to public HTML responses.
pub fn apply_public_html_headers(res: &mut Response) {
    let headers = res.headers_mut();
    headers.insert(
        X_ROBOTS_TAG.clone(),
        HeaderValue::from_static(NOINDEX_NOFOLLOW),
    );
    headers.insert(
        CONTENT_SECURITY_POLICY,
        HeaderValue::from_static(PUBLIC_HTML_CSP),
    );
}
