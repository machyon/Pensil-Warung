mod common;

use axum::http::StatusCode;
use common::TestApp;
use serde_json::json;

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

#[tokio::test]
async fn username_can_be_changed() {
    let (app, token) = app_with_siti().await;
    let res = app
        .patch_json(
            "/api/v1/me/username",
            Some(&token),
            &json!({"username": "warung_siti"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["username"], "warung_siti");
    let me = app.get("/api/v1/me", Some(&token)).await;
    assert_eq!(me.json["username"], "warung_siti");
}

#[tokio::test]
async fn username_rejects_bad_format() {
    let (app, token) = app_with_siti().await;
    for bad in ["ab", "Siti", "siti rahayu", "siti-1", &"a".repeat(31)] {
        let res = app
            .patch_json(
                "/api/v1/me/username",
                Some(&token),
                &json!({ "username": bad }),
            )
            .await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}");
        assert_eq!(res.json["error"]["code"], "invalid_value");
    }
}

#[tokio::test]
async fn username_taken_is_409() {
    let (app, token) = app_with_siti().await;
    app.register("Budi", "budi@example.com", "rahasia123").await;
    let res = app
        .patch_json(
            "/api/v1/me/username",
            Some(&token),
            &json!({"username": "budi"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    assert_eq!(res.json["error"]["code"], "username_taken");
}
