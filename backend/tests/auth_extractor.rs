mod common;

use axum::http::StatusCode;
use backend::auth::jwt::issue_token;
use common::{TEST_JWT_SECRET, TestApp};
use serde_json::Value;
use time::Duration;
use uuid::Uuid;

fn token(id: Uuid, version: i32, expires_in: Duration) -> String {
    issue_token(TEST_JWT_SECRET, id, 1, version, expires_in).unwrap()
}

async fn user_id(app: &TestApp) -> Uuid {
    app.client()
        .await
        .query_one("SELECT id FROM users", &[])
        .await
        .unwrap()
        .get(0)
}

async fn code_of(app: &TestApp, token: Option<&str>) -> (StatusCode, Value) {
    let res = app.get("/api/v1/me", token).await;
    (res.status, res.json["error"]["code"].clone())
}

#[tokio::test]
async fn valid_token_passes() {
    let app = TestApp::new().await;
    let t = app.register("Siti", "siti@example.com", "rahasia123").await;
    assert_eq!(code_of(&app, Some(&t)).await.0, StatusCode::OK);
}

#[tokio::test]
async fn missing_malformed_expired_and_forged_are_unauthorized() {
    let app = TestApp::new().await;
    app.register("Siti", "siti@example.com", "rahasia123").await;
    let id = user_id(&app).await;
    let good = token(id, 0, Duration::days(7));
    let other = issue_token(TEST_JWT_SECRET, id, 2, 0, Duration::days(7)).unwrap();
    // Payload of another token under this token's signature.
    let forged = format!(
        "{}.{}.{}",
        good.split('.').next().unwrap(),
        other.split('.').nth(1).unwrap(),
        good.split('.').nth(2).unwrap()
    );
    for t in [
        None,
        Some("junk"),
        Some(&token(id, 0, Duration::seconds(-5))[..]),
        Some(&forged),
    ] {
        let (status, code) = code_of(&app, t).await;
        assert_eq!(
            (status, code.as_str()),
            (StatusCode::UNAUTHORIZED, Some("unauthorized"))
        );
    }
}

#[tokio::test]
async fn wrong_version_is_unauthorized_and_unknown_user_is_account_gone() {
    let app = TestApp::new().await;
    app.register("Siti", "siti@example.com", "rahasia123").await;
    let id = user_id(&app).await;
    let (status, code) = code_of(&app, Some(&token(id, 1, Duration::days(1)))).await;
    assert_eq!(
        (status, code.as_str()),
        (StatusCode::UNAUTHORIZED, Some("unauthorized"))
    );
    let (status, code) = code_of(&app, Some(&token(Uuid::new_v4(), 0, Duration::days(1)))).await;
    assert_eq!(
        (status, code.as_str()),
        (StatusCode::UNAUTHORIZED, Some("account_gone"))
    );
}
