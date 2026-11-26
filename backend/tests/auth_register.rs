mod common;

use axum::http::StatusCode;
use common::TestApp;
use serde_json::json;

fn body(name: &str, email: &str, password: &str) -> serde_json::Value {
    json!({ "display_name": name, "email": email, "password": password })
}

#[tokio::test]
async fn register_ok_returns_token_and_user() {
    let app = TestApp::new().await;
    let res = app
        .post_json(
            "/api/v1/auth/register",
            None,
            &body("Siti Rahayu", "  Siti@Example.COM ", "rahasia123"),
        )
        .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let user = &res.json["user"];
    assert_eq!(user["email"], "siti@example.com");
    assert_eq!(user["display_name"], "Siti Rahayu");
    assert_eq!(user["username"], "siti_rahayu");
    assert_eq!(user["role"], "user");
    assert_eq!(user["has_password"], true);
    assert_eq!(user["permissions"].as_array().unwrap().len(), 6);
    assert!(res.json["token"].as_str().is_some_and(|t| !t.is_empty()));
    assert!(!res.text.contains("rahasia123"));
}

#[tokio::test]
async fn duplicate_email_is_409() {
    let app = TestApp::new().await;
    let first = body("Budi", "budi@example.com", "rahasia123");
    assert_eq!(
        app.post_json("/api/v1/auth/register", None, &first)
            .await
            .status,
        StatusCode::CREATED
    );
    let again = body("Budi Lain", "BUDI@example.com", "rahasia123");
    let res = app.post_json("/api/v1/auth/register", None, &again).await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    assert_eq!(res.json["error"]["code"], "email_taken");
}

#[tokio::test]
async fn short_password_is_rejected() {
    let app = TestApp::new().await;
    let res = app
        .post_json(
            "/api/v1/auth/register",
            None,
            &body("Budi", "budi@example.com", "pendek"),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "invalid_value");
    assert_eq!(res.json["error"]["details"]["field"], "password");
}

#[tokio::test]
async fn same_display_name_gets_numbered_usernames() {
    let app = TestApp::new().await;
    let mut names = Vec::new();
    for email in ["a@example.com", "b@example.com"] {
        let res = app
            .post_json(
                "/api/v1/auth/register",
                None,
                &body("Siti Rahayu", email, "rahasia123"),
            )
            .await;
        assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
        names.push(res.json["user"]["username"].as_str().unwrap().to_owned());
    }
    assert_eq!(names, ["siti_rahayu", "siti_rahayu_1"]);
}

#[tokio::test]
async fn blank_display_name_falls_back_to_generated_name() {
    let app = TestApp::new().await;
    let res = app
        .post_json(
            "/api/v1/auth/register",
            None,
            &body("!!!", "x@example.com", "rahasia123"),
        )
        .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    assert!(
        res.json["user"]["display_name"]
            .as_str()
            .unwrap()
            .starts_with("user ")
    );
}
