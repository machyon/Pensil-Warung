mod common;

use axum::Router;
use axum::http::StatusCode;
use axum::http::header::CACHE_CONTROL;
use axum::routing::get;
use common::TestApp;
use jsonwebtoken::{Algorithm, EncodingKey, Header, encode};
use serde_json::{Value, json};
use time::OffsetDateTime;
use uuid::Uuid;

const CLIENT_ID: &str = "test-client.apps.googleusercontent.com";
const PRIVATE_KEY: &str = include_str!("fixtures/google_test_key.pem");
const JWKS: &str = include_str!("fixtures/google_jwks.json");

/// App whose Google verifier trusts the fixture key, served from a local mock JWKS.
async fn google_app() -> TestApp {
    let router = Router::new().route(
        "/certs",
        get(|| async { ([(CACHE_CONTROL, "public, max-age=3600")], JWKS) }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/certs", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    TestApp::with_config(|config| {
        config.google_client_ids = vec![CLIENT_ID.to_owned()];
        config.google_jwks_url = url;
    })
    .await
}

/// A signed Google ID token for `sub`, issued `age_secs` ago.
fn id_token(sub: &str, age_secs: i64) -> String {
    let now = OffsetDateTime::now_utc().unix_timestamp();
    let claims = json!({
        "iss": "https://accounts.google.com", "aud": CLIENT_ID, "sub": sub,
        "email": "budi@example.com", "email_verified": true,
        "iat": now - age_secs, "exp": now + 3600,
    });
    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some("test-key".to_owned());
    let key = EncodingKey::from_rsa_pem(PRIVATE_KEY.as_bytes()).unwrap();
    encode(&header, &claims, &key).unwrap()
}

async fn google_sub(app: &TestApp) -> String {
    app.client()
        .await
        .query_one(
            "SELECT provider_user_id FROM auth_identities WHERE provider = 'google'",
            &[],
        )
        .await
        .unwrap()
        .get(0)
}

async fn delete_with(app: &TestApp, token: &str, body: Value) -> common::TestResponse {
    app.delete_json("/api/v1/me", Some(token), Some(&body))
        .await
}

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
    assert_eq!(res.json["error"]["details"]["field"], "new_password");
    let long = app
        .put_json(
            "/api/v1/me/password",
            Some(&token),
            &json!({"current_password": "rahasia123", "new_password": "x".repeat(129)}),
        )
        .await;
    assert_eq!(long.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(long.json["error"]["details"]["field"], "new_password");
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

#[tokio::test]
async fn delete_with_password_cascades_and_keeps_broadcasts() {
    let (app, token) = app_with_siti().await;
    let db = app.client().await;
    let id: Uuid = db
        .query_one("SELECT id FROM users", &[])
        .await
        .unwrap()
        .get(0);
    db.execute(
        "INSERT INTO broadcasts (category, title, summary, status, broadcasted_at, created_by)
         VALUES ('update', 'Halo', 'Ringkasan', 'sent', now(), $1)",
        &[&id],
    )
    .await
    .unwrap();

    let res = delete_with(&app, &token, json!({"current_password": "rahasia123"})).await;
    assert_eq!(res.status, StatusCode::NO_CONTENT, "{}", res.text);

    let count = |sql: &'static str| {
        let db = &db;
        async move { db.query_one(sql, &[]).await.unwrap().get::<_, i64>(0) }
    };
    assert_eq!(count("SELECT count(*) FROM users").await, 0);
    assert_eq!(count("SELECT count(*) FROM auth_identities").await, 0);
    assert_eq!(
        count("SELECT count(*) FROM broadcasts WHERE created_by IS NULL").await,
        1
    );

    let me = app.get("/api/v1/me", Some(&token)).await;
    assert_eq!(me.status, StatusCode::UNAUTHORIZED);
    assert_eq!(me.json["error"]["code"], "account_gone");
}

#[tokio::test]
async fn delete_wrong_or_missing_password_is_rejected() {
    let (app, token) = app_with_siti().await;
    let res = delete_with(&app, &token, json!({"current_password": "salah-salah"})).await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
    assert_eq!(res.json["error"]["code"], "invalid_credentials");
    let res = delete_with(&app, &token, json!({})).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        app.get("/api/v1/me", Some(&token)).await.status,
        StatusCode::OK
    );
}

#[tokio::test]
async fn delete_google_only_with_fresh_token() {
    let app = google_app().await;
    let token = app.google_user("Budi", "budi@example.com").await;
    let sub = google_sub(&app).await;
    let res = delete_with(&app, &token, json!({"id_token": id_token(&sub, 60)})).await;
    assert_eq!(res.status, StatusCode::NO_CONTENT, "{}", res.text);
    let me = app.get("/api/v1/me", Some(&token)).await;
    assert_eq!(me.json["error"]["code"], "account_gone");
}

#[tokio::test]
async fn delete_google_only_needs_a_fresh_matching_token() {
    let app = google_app().await;
    let token = app.google_user("Budi", "budi@example.com").await;
    let sub = google_sub(&app).await;
    let bodies = [
        json!({"id_token": id_token(&sub, 600)}),
        json!({"id_token": id_token(&sub, -600)}),
        json!({"id_token": id_token("someone-else", 0)}),
        json!({"current_password": "apa-saja-123"}),
        json!({}),
    ];
    for body in bodies {
        let res = delete_with(&app, &token, body.clone()).await;
        assert_eq!(res.status, StatusCode::UNAUTHORIZED, "{body}");
        assert_eq!(res.json["error"]["code"], "reauth_required", "{body}");
    }
    assert_eq!(
        app.get("/api/v1/me", Some(&token)).await.status,
        StatusCode::OK
    );
}

/// Logs in and returns the token.
async fn login(app: &TestApp, email: &str, password: &str) -> String {
    let res = app
        .post_json(
            "/api/v1/auth/login",
            None,
            &json!({"email": email, "password": password}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    res.json["token"].as_str().unwrap().to_owned()
}

async fn assert_revoked(app: &TestApp, token: &str) {
    let res = app.get("/api/v1/me", Some(token)).await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
    assert_eq!(res.json["error"]["code"], "unauthorized");
}

#[tokio::test]
async fn email_change_revokes_every_older_token() {
    let (app, token) = app_with_siti().await;
    let device2 = login(&app, "siti@example.com", "rahasia123").await;
    let budi = app.register("Budi", "budi@example.com", "rahasia123").await;
    let res = app
        .patch_json(
            "/api/v1/me/email",
            Some(&token),
            &json!({"email": "baru@example.com", "current_password": "rahasia123"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_revoked(&app, &token).await;
    assert_revoked(&app, &device2).await;
    let fresh = login(&app, "baru@example.com", "rahasia123").await;
    assert_eq!(
        app.get("/api/v1/me", Some(&fresh)).await.status,
        StatusCode::OK
    );
    assert_eq!(
        app.get("/api/v1/me", Some(&budi)).await.status,
        StatusCode::OK
    );
}

#[tokio::test]
async fn password_change_revokes_every_older_token() {
    let (app, token) = app_with_siti().await;
    let device2 = login(&app, "siti@example.com", "rahasia123").await;
    let budi = app.register("Budi", "budi@example.com", "rahasia123").await;
    let res = app
        .put_json(
            "/api/v1/me/password",
            Some(&token),
            &json!({"current_password": "rahasia123", "new_password": "sandi-baru-456"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::NO_CONTENT, "{}", res.text);
    assert_revoked(&app, &token).await;
    assert_revoked(&app, &device2).await;
    let fresh = login(&app, "siti@example.com", "sandi-baru-456").await;
    assert_eq!(
        app.get("/api/v1/me", Some(&fresh)).await.status,
        StatusCode::OK
    );
    assert_eq!(
        app.get("/api/v1/me", Some(&budi)).await.status,
        StatusCode::OK
    );
}
