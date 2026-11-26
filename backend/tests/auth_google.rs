mod common;

use axum::Router;
use axum::http::StatusCode;
use axum::http::header::CACHE_CONTROL;
use axum::routing::get;
use common::{TestApp, TestResponse};
use jsonwebtoken::{Algorithm, EncodingKey, Header, encode};
use serde_json::{Value, json};
use time::OffsetDateTime;

const CLIENT_ID: &str = "test-client.apps.googleusercontent.com";
const PRIVATE_KEY: &str = include_str!("fixtures/google_test_key.pem");
const JWKS: &str = include_str!("fixtures/google_jwks.json");

/// Serves the fixture JWKS on a random local port, standing in for Google.
async fn mock_jwks() -> String {
    let app = Router::new().route(
        "/certs",
        get(|| async { ([(CACHE_CONTROL, "public, max-age=3600")], JWKS) }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/certs", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    url
}

async fn app() -> TestApp {
    let url = mock_jwks().await;
    TestApp::with_config(|config| {
        config.google_client_ids = vec![CLIENT_ID.to_owned()];
        config.google_jwks_url = url;
    })
    .await
}

fn claims(overrides: Value) -> Value {
    let now = OffsetDateTime::now_utc().unix_timestamp();
    let mut base = json!({
        "iss": "https://accounts.google.com",
        "aud": CLIENT_ID,
        "sub": "google-sub-1",
        "email": "Warung@Example.com",
        "email_verified": true,
        "name": "Siti Rahayu",
        "iat": now,
        "exp": now + 3600,
    });
    base.as_object_mut()
        .unwrap()
        .extend(overrides.as_object().unwrap().clone());
    base
}

fn sign(claims: &Value) -> String {
    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some("test-key".to_owned());
    let key = EncodingKey::from_rsa_pem(PRIVATE_KEY.as_bytes()).unwrap();
    encode(&header, claims, &key).unwrap()
}

async fn google(app: &TestApp, overrides: Value) -> TestResponse {
    let token = sign(&claims(overrides));
    app.post_json("/api/v1/auth/google", None, &json!({ "id_token": token }))
        .await
}

#[tokio::test]
async fn new_google_user_is_created_then_logs_in() {
    let app = app().await;
    let first = google(&app, json!({})).await;
    assert_eq!(first.status, StatusCode::CREATED, "{}", first.text);
    assert_eq!(first.json["created"], true);
    assert_eq!(first.json["user"]["email"], "warung@example.com");
    assert_eq!(first.json["user"]["display_name"], "Siti Rahayu");
    assert_eq!(first.json["user"]["has_password"], false);
    assert!(first.json["token"].as_str().is_some_and(|t| !t.is_empty()));

    let again = google(&app, json!({})).await;
    assert_eq!(again.status, StatusCode::OK, "{}", again.text);
    assert_eq!(again.json["created"], false);
    assert_eq!(again.json["user"]["id"], first.json["user"]["id"]);
}

#[tokio::test]
async fn email_with_a_password_account_is_409() {
    let app = app().await;
    let res = app
        .post_json(
            "/api/v1/auth/register",
            None,
            &json!({"display_name": "Siti", "email": "warung@example.com", "password": "rahasia123"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::CREATED);

    let res = google(&app, json!({})).await;
    assert_eq!(res.status, StatusCode::CONFLICT, "{}", res.text);
    assert_eq!(res.json["error"]["code"], "email_registered");
    let count = app
        .client()
        .await
        .query_one("SELECT count(*) FROM auth_identities", &[])
        .await
        .unwrap()
        .get::<_, i64>(0);
    assert_eq!(count, 1, "no google identity may be linked");
}

#[tokio::test]
async fn bad_tokens_are_401() {
    let app = app().await;
    let now = OffsetDateTime::now_utc().unix_timestamp();
    let cases = [
        ("aud", json!({"aud": "someone-else"})),
        ("iss", json!({"iss": "https://evil.example.com"})),
        ("expired", json!({"exp": now - 10})),
        ("unverified", json!({"email_verified": false})),
    ];
    for (what, overrides) in cases {
        let res = google(&app, overrides).await;
        assert_eq!(res.status, StatusCode::UNAUTHORIZED, "{what}: {}", res.text);
        assert_eq!(res.json["error"]["code"], "unauthorized", "{what}");
    }

    // Right claims, signature from a different key (tampered payload).
    let token = sign(&claims(json!({})));
    let mut parts: Vec<&str> = token.split('.').collect();
    let forged = sign(&claims(json!({"sub": "someone-else"})));
    parts[1] = forged.split('.').nth(1).unwrap();
    let res = app
        .post_json(
            "/api/v1/auth/google",
            None,
            &json!({ "id_token": parts.join(".") }),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
    let res = app
        .post_json("/api/v1/auth/google", None, &json!({"id_token": "junk"}))
        .await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
}
