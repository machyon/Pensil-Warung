//! HTTP router: routes plus the tower layers every request passes through.

use std::time::Duration;

use axum::extract::{DefaultBodyLimit, Request, State};
use axum::http::{HeaderName, HeaderValue, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde_json::json;
use tower::ServiceBuilder;
use tower_http::request_id::{
    MakeRequestId, PropagateRequestIdLayer, RequestId, SetRequestIdLayer,
};
use tower_http::trace::{DefaultOnResponse, TraceLayer};
use tracing::Level;
use uuid::Uuid;

use crate::error::{AppError, AppResult, ErrorCode};
use crate::state::AppState;

const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
/// Default body limit; routes that need more (photo upload) override it.
const BODY_LIMIT_BYTES: usize = 64 * 1024;
const REQUEST_ID_HEADER: &str = "x-request-id";

pub fn router(state: AppState) -> Router {
    with_layers(api_routes(), state)
}

/// Every route of the API. Feature routers are nested under `/api/v1` here.
fn api_routes() -> Router<AppState> {
    let v1 = Router::new().route("/health/db", get(health_db));
    Router::new()
        .route("/health", get(health))
        .nest("/api/v1", v1)
}

/// Adds the fallback and the layers. Split from `router` so tests can add routes.
///
/// `ServiceBuilder` lists layers outermost first:
/// 1. `SetRequestId` runs first so every later layer and log sees an id.
/// 2. `Trace` wraps the rest, so timeouts and errors are logged with the id and status.
/// 3. `PropagateRequestId` copies the id onto the response.
/// 4. The timeout sits innermost, closest to the handlers, so it measures handler time.
///
/// `DefaultBodyLimit` only sets a request extension that the body extractors read,
/// so its position does not matter and routes can override it with their own.
fn with_layers(routes: Router<AppState>, state: AppState) -> Router {
    let request_id = HeaderName::from_static(REQUEST_ID_HEADER);
    routes
        .fallback(not_found)
        .layer(DefaultBodyLimit::max(BODY_LIMIT_BYTES))
        .layer(middleware::from_fn(timeout))
        .layer(
            ServiceBuilder::new()
                .layer(SetRequestIdLayer::new(request_id.clone(), UuidRequestId))
                .layer(
                    TraceLayer::new_for_http()
                        .on_response(DefaultOnResponse::new().level(Level::INFO))
                        .make_span_with(|req: &Request| {
                            // Only method, path and request id. Never bodies or Authorization.
                            let request_id = req
                                .headers()
                                .get(REQUEST_ID_HEADER)
                                .and_then(|v| v.to_str().ok())
                                .unwrap_or("-");
                            tracing::info_span!(
                                "request",
                                method = %req.method(),
                                path = %req.uri().path(),
                                request_id = %request_id,
                            )
                        }),
                )
                .layer(PropagateRequestIdLayer::new(request_id)),
        )
        .with_state(state)
}

#[derive(Clone, Copy)]
struct UuidRequestId;

impl MakeRequestId for UuidRequestId {
    fn make_request_id<B>(&mut self, _request: &axum::http::Request<B>) -> Option<RequestId> {
        HeaderValue::from_str(&Uuid::new_v4().to_string())
            .ok()
            .map(RequestId::new)
    }
}

/// Cancels requests that run longer than `REQUEST_TIMEOUT` and answers with the
/// JSON error shape. tower-http's `TimeoutLayer` can only return a bare status
/// code with an empty body, and `HandleErrorLayer` would need an extra error type
/// conversion, so a small `from_fn` middleware is the simplest way to get JSON.
async fn timeout(req: Request, next: Next) -> Response {
    match tokio::time::timeout(REQUEST_TIMEOUT, next.run(req)).await {
        Ok(response) => response,
        Err(_) => AppError::internal()
            .with_status(StatusCode::GATEWAY_TIMEOUT)
            .with_message("Permintaan terlalu lama diproses. Coba lagi sebentar.")
            .into_response(),
    }
}

async fn not_found() -> AppError {
    AppError::new(ErrorCode::NotFound)
}

/// Liveness only. Must not touch the database (Render health check).
async fn health() -> impl IntoResponse {
    Json(json!({ "status": "ok" }))
}

/// Readiness: one round trip to the database.
async fn health_db(State(state): State<AppState>) -> AppResult<Json<serde_json::Value>> {
    let client = state.pool.get().await?;
    client.query_one("SELECT 1", &[]).await?;
    Ok(Json(json!({ "status": "ok" })))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::common::extract::ApiJson;
    use crate::config::Config;
    use crate::db;
    use axum::body::Body;
    use axum::routing::post;
    use http_body_util::BodyExt;
    use std::sync::Arc;
    use tower::ServiceExt;

    fn test_state(database_url: &str) -> AppState {
        let config = Config::from_lookup(|key| match key {
            "DATABASE_URL" => Some(database_url.to_owned()),
            _ => None,
        })
        .expect("config");
        let pool = db::create_pool(&config).expect("pool");
        AppState {
            pool,
            config: Arc::new(config),
        }
    }

    /// The pool connects lazily, so this state is fine for routes without a DB.
    /// Port 1 refuses connections, which also exercises the 503 path.
    fn offline_state() -> AppState {
        test_state("postgres://postgres@127.0.0.1:1/postgres")
    }

    fn test_app(state: AppState) -> Router {
        let routes = api_routes().route(
            "/test/echo",
            post(|ApiJson(v): ApiJson<serde_json::Value>| async move { ApiJson(v) }),
        );
        with_layers(routes, state)
    }

    async fn send(app: Router, req: axum::http::Request<Body>) -> (Response, serde_json::Value) {
        let response = app.oneshot(req).await.expect("response");
        let (parts, body) = response.into_parts();
        let bytes = body.collect().await.expect("body").to_bytes();
        let json = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
        (Response::from_parts(parts, Body::empty()), json)
    }

    fn get_req(path: &str) -> axum::http::Request<Body> {
        axum::http::Request::get(path)
            .body(Body::empty())
            .expect("request")
    }

    #[tokio::test]
    async fn health_is_ok_without_database() {
        let (response, json) = send(test_app(offline_state()), get_req("/health")).await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(json, json!({ "status": "ok" }));
    }

    #[tokio::test]
    async fn bad_json_returns_error_envelope() {
        let req = axum::http::Request::post("/test/echo")
            .header("content-type", "application/json")
            .body(Body::from("{oops"))
            .expect("request");
        let (response, json) = send(test_app(offline_state()), req).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert_eq!(json["error"]["code"], "invalid_body");
    }

    #[tokio::test]
    async fn body_over_limit_is_413() {
        let big = format!(r#"{{"x":"{}"}}"#, "a".repeat(BODY_LIMIT_BYTES));
        let req = axum::http::Request::post("/test/echo")
            .header("content-type", "application/json")
            .body(Body::from(big))
            .expect("request");
        let (response, json) = send(test_app(offline_state()), req).await;
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
        assert_eq!(json["error"]["code"], "payload_too_large");
    }

    #[tokio::test]
    async fn unknown_path_is_json_404() {
        let (response, json) = send(test_app(offline_state()), get_req("/nope")).await;
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        assert_eq!(json["error"]["code"], "not_found");
    }

    #[tokio::test]
    async fn request_id_is_generated_when_missing() {
        let (response, _) = send(test_app(offline_state()), get_req("/health")).await;
        let id = response.headers().get("x-request-id").expect("header");
        assert!(Uuid::parse_str(id.to_str().unwrap()).is_ok());
    }

    #[tokio::test]
    async fn request_id_is_echoed_when_supplied() {
        let req = axum::http::Request::get("/health")
            .header("x-request-id", "abc-123")
            .body(Body::empty())
            .expect("request");
        let (response, _) = send(test_app(offline_state()), req).await;
        assert_eq!(response.headers()["x-request-id"], "abc-123");
    }

    #[tokio::test]
    async fn health_db_is_503_when_database_is_down() {
        let (response, json) = send(test_app(offline_state()), get_req("/api/v1/health/db")).await;
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(json["error"]["code"], "db_unavailable");
    }

    #[tokio::test]
    #[ignore = "needs TEST_DATABASE_URL (Postgres 18)"]
    async fn health_db_is_ok_with_database() {
        let url = std::env::var("TEST_DATABASE_URL").expect("TEST_DATABASE_URL");
        let (response, json) = send(test_app(test_state(&url)), get_req("/api/v1/health/db")).await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(json, json!({ "status": "ok" }));
    }
}
