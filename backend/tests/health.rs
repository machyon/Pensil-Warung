mod common;

use axum::http::StatusCode;
use common::TestApp;
use serde_json::json;

#[tokio::test]
async fn health_is_ok() {
    let app = TestApp::new().await;
    let res = app.get("/health", None).await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.json, json!({ "status": "ok" }));
}

#[tokio::test]
async fn health_db_is_ok() {
    let app = TestApp::new().await;
    let res = app.get("/api/v1/health/db", None).await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.json, json!({ "status": "ok" }));
}

#[tokio::test]
async fn unknown_route_is_json_404() {
    let app = TestApp::new().await;
    let res = app.get("/api/v1/nope", None).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    assert_eq!(res.json["error"]["code"], "not_found");
}

#[tokio::test]
async fn responses_carry_a_request_id() {
    let app = TestApp::new().await;
    let res = app.get("/health", None).await;
    assert!(res.headers.contains_key("x-request-id"));
}
