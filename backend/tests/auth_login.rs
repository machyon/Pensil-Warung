mod common;

use axum::http::StatusCode;
use common::TestApp;
use serde_json::json;

async fn registered() -> TestApp {
    let app = TestApp::new().await;
    let res = app
        .post_json(
            "/api/v1/auth/register",
            None,
            &json!({"display_name": "Siti", "email": "siti@example.com", "password": "rahasia123"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::CREATED);
    app
}

fn login(email: &str, password: &str) -> serde_json::Value {
    json!({ "email": email, "password": password })
}

#[tokio::test]
async fn login_ok() {
    let app = registered().await;
    let res = app
        .post_json(
            "/api/v1/auth/login",
            None,
            &login(" SITI@example.com ", "rahasia123"),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["user"]["email"], "siti@example.com");
    assert_eq!(res.json["user"]["role"], "user");
    assert!(res.json["token"].as_str().is_some_and(|t| !t.is_empty()));
}

#[tokio::test]
async fn wrong_password_and_unknown_email_look_the_same() {
    let app = registered().await;
    let wrong = app
        .post_json(
            "/api/v1/auth/login",
            None,
            &login("siti@example.com", "salah-banget"),
        )
        .await;
    let unknown = app
        .post_json(
            "/api/v1/auth/login",
            None,
            &login("nobody@example.com", "rahasia123"),
        )
        .await;
    assert_eq!(wrong.status, StatusCode::UNAUTHORIZED);
    assert_eq!(unknown.status, StatusCode::UNAUTHORIZED);
    assert_eq!(wrong.json["error"]["code"], "invalid_credentials");
    assert_eq!(wrong.json, unknown.json);
}

#[tokio::test]
async fn google_only_account_gets_invalid_credentials() {
    let app = TestApp::new().await;
    let client = app.client().await;
    let id: uuid::Uuid = client
        .query_one(
            "INSERT INTO users (email, display_name) VALUES ('g@example.com', 'Gina') RETURNING id",
            &[],
        )
        .await
        .unwrap()
        .get(0);
    client
        .execute(
            "INSERT INTO auth_identities (user_id, provider, provider_user_id)
             VALUES ($1, 'google', 'sub-1')",
            &[&id],
        )
        .await
        .unwrap();
    let res = app
        .post_json(
            "/api/v1/auth/login",
            None,
            &login("g@example.com", "rahasia123"),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
    assert_eq!(res.json["error"]["code"], "invalid_credentials");
}
