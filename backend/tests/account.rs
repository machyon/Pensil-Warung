mod common;

use axum::http::StatusCode;
use common::TestApp;

async fn app_with_siti() -> (TestApp, String) {
    let app = TestApp::new().await;
    let token = app
        .register("Siti Rahayu", "siti@example.com", "rahasia123")
        .await;
    (app, token)
}

#[tokio::test]
async fn me_returns_profile() {
    let (app, token) = app_with_siti().await;
    let res = app.get("/api/v1/me", Some(&token)).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["email"], "siti@example.com");
    assert_eq!(res.json["username"], "siti_rahayu");
    assert_eq!(res.json["has_password"], true);
}

#[tokio::test]
async fn me_needs_a_token() {
    let app = TestApp::new().await;
    let res = app.get("/api/v1/me", None).await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
    assert_eq!(res.json["error"]["code"], "unauthorized");
}

#[tokio::test]
async fn me_for_google_user_has_no_password() {
    let app = TestApp::new().await;
    let token = app.google_user("Budi", "budi@example.com").await;
    let res = app.get("/api/v1/me", Some(&token)).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["has_password"], false);
}
