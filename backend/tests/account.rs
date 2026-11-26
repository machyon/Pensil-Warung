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

#[tokio::test]
async fn display_name_is_sanitized_and_username_kept() {
    let (app, token) = app_with_siti().await;
    let res = app
        .patch_json(
            "/api/v1/me/display-name",
            Some(&token),
            &json!({"display_name": "  Déwi   Sartika!! "}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["display_name"], "Dewi Sartika");
    assert_eq!(res.json["username"], "siti_rahayu");
}

#[tokio::test]
async fn display_name_rejects_empty_after_cleaning_and_too_long() {
    let (app, token) = app_with_siti().await;
    for bad in ["!!!", "   ", "", &"a".repeat(51)] {
        let res = app
            .patch_json(
                "/api/v1/me/display-name",
                Some(&token),
                &json!({ "display_name": bad }),
            )
            .await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}");
        assert_eq!(res.json["error"]["code"], "invalid_name");
    }
}

#[tokio::test]
async fn email_changes_with_correct_password_and_is_normalized() {
    let (app, token) = app_with_siti().await;
    let res = app
        .patch_json(
            "/api/v1/me/email",
            Some(&token),
            &json!({"email": " Baru@Example.com ", "current_password": "rahasia123"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["email"], "baru@example.com");
    let login = app
        .post_json(
            "/api/v1/auth/login",
            None,
            &json!({"email": "baru@example.com", "password": "rahasia123"}),
        )
        .await;
    assert_eq!(login.status, StatusCode::OK);
}

#[tokio::test]
async fn email_wrong_password_is_401() {
    let (app, token) = app_with_siti().await;
    let res = app
        .patch_json(
            "/api/v1/me/email",
            Some(&token),
            &json!({"email": "baru@example.com", "current_password": "salah-banget"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
    assert_eq!(res.json["error"]["code"], "invalid_credentials");
    let me = app.get("/api/v1/me", Some(&token)).await;
    assert_eq!(me.json["email"], "siti@example.com");
}

#[tokio::test]
async fn email_taken_is_409() {
    let (app, token) = app_with_siti().await;
    app.register("Budi", "budi@example.com", "rahasia123").await;
    let res = app
        .patch_json(
            "/api/v1/me/email",
            Some(&token),
            &json!({"email": "BUDI@example.com", "current_password": "rahasia123"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    assert_eq!(res.json["error"]["code"], "email_taken");
}

#[tokio::test]
async fn email_rejects_malformed() {
    let (app, token) = app_with_siti().await;
    let res = app
        .patch_json(
            "/api/v1/me/email",
            Some(&token),
            &json!({"email": "bukan-email", "current_password": "rahasia123"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "invalid_value");
}

#[tokio::test]
async fn email_google_only_is_403() {
    let app = TestApp::new().await;
    let token = app.google_user("Budi", "budi@example.com").await;
    let res = app
        .patch_json(
            "/api/v1/me/email",
            Some(&token),
            &json!({"email": "baru@example.com", "current_password": "apa-saja-123"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::FORBIDDEN);
    assert_eq!(res.json["error"]["code"], "google_account");
}

#[tokio::test]
async fn password_change_works_for_login() {
    let (app, token) = app_with_siti().await;
    let res = app
        .put_json(
            "/api/v1/me/password",
            Some(&token),
            &json!({"current_password": "rahasia123", "new_password": "sandi-baru-456"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::NO_CONTENT, "{}", res.text);
    let login = |pw: &str| json!({"email": "siti@example.com", "password": pw});
    let old = app
        .post_json("/api/v1/auth/login", None, &login("rahasia123"))
        .await;
    assert_eq!(old.status, StatusCode::UNAUTHORIZED);
    let new = app
        .post_json("/api/v1/auth/login", None, &login("sandi-baru-456"))
        .await;
    assert_eq!(new.status, StatusCode::OK);
}

#[tokio::test]
async fn password_wrong_current_is_401() {
    let (app, token) = app_with_siti().await;
    let res = app
        .put_json(
            "/api/v1/me/password",
            Some(&token),
            &json!({"current_password": "salah-banget", "new_password": "sandi-baru-456"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
    assert_eq!(res.json["error"]["code"], "invalid_credentials");
}

#[tokio::test]
async fn password_too_short_is_422() {
    let (app, token) = app_with_siti().await;
    let res = app
        .put_json(
            "/api/v1/me/password",
            Some(&token),
            &json!({"current_password": "rahasia123", "new_password": "pendek"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "invalid_value");
}

#[tokio::test]
async fn password_google_only_is_403() {
    let app = TestApp::new().await;
    let token = app.google_user("Budi", "budi@example.com").await;
    let res = app
        .put_json(
            "/api/v1/me/password",
            Some(&token),
            &json!({"current_password": "apa-saja-123", "new_password": "sandi-baru-456"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::FORBIDDEN);
    assert_eq!(res.json["error"]["code"], "google_account");
}
