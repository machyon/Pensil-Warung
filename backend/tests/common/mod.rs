//! Integration-test harness.
//!
//! `TestApp::new().await` creates a fresh database `pw_test_<uuid>` on the
//! server in `TEST_DATABASE_URL`, runs the migrations on it and builds the real
//! `Router`. Requests go through `tower::ServiceExt::oneshot`, so no TCP port is
//! opened. Every `TestApp` has its own database, so tests can run in parallel.
//! The database is dropped when the `TestApp` is dropped, even if the test panics.

// Each test binary uses a different subset of these helpers.
#![allow(dead_code)]

use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::http::{HeaderMap, Method, Request, StatusCode, header};
use backend::auth::perms::Permissions;
use backend::config::Config;
use backend::db;
use backend::routes;
use backend::state::AppState;
use deadpool_postgres::{Object, Pool};
use http_body_util::BodyExt;
use serde_json::Value;
use tower::ServiceExt;
use uuid::Uuid;

/// Fixed signing key for tests (at least 32 characters).
pub const TEST_JWT_SECRET: &str = "pensil-warung-test-jwt-secret-0123456789";

pub struct TestApp {
    pub router: Router,
    pub pool: Pool,
    pub config: Arc<Config>,
    /// Name of this test's database, `pw_test_<uuid>`.
    pub db_name: String,
    /// `TEST_DATABASE_URL` as given, used to create and drop the database.
    admin_url: String,
}

pub struct TestResponse {
    pub status: StatusCode,
    pub headers: HeaderMap,
    /// The body parsed as JSON, or `Value::Null` when it is empty or not JSON.
    pub json: Value,
    pub text: String,
}

impl TestApp {
    /// A fresh app with the default test config.
    pub async fn new() -> Self {
        Self::with_config(|_| {}).await
    }

    /// Like `new`, but `customize` can change the config before the app is built.
    pub async fn with_config(customize: impl FnOnce(&mut Config)) -> Self {
        let admin_url = std::env::var("TEST_DATABASE_URL")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .expect(
                "TEST_DATABASE_URL is not set. Integration tests need a PostgreSQL 18 server \
                 whose role can create databases, for example \
                 TEST_DATABASE_URL=postgres://postgres@localhost:5432/postgres cargo test",
            );

        let db_name = format!("pw_test_{}", Uuid::new_v4().simple());
        let admin = db::create_pool(&test_config(&admin_url)).expect("admin pool");
        admin
            .get()
            .await
            .expect("connect to TEST_DATABASE_URL")
            .batch_execute(&format!("CREATE DATABASE {db_name}"))
            .await
            .expect("create test database");
        admin.close();

        let mut config = test_config(&with_database(&admin_url, &db_name));
        customize(&mut config);
        let pool = db::create_pool(&config).expect("test pool");
        let config = Arc::new(config);
        let state = AppState {
            pool: pool.clone(),
            config: config.clone(),
            perms: Arc::default(),
            google_keys: Arc::default(),
        };

        // Built before the migrations, so a failure below still drops the database.
        // The real router needs the seeded permissions, so it replaces this one after.
        let mut app = TestApp {
            router: Router::new(),
            pool,
            config,
            db_name,
            admin_url,
        };
        db::run_migrations(&app.pool)
            .await
            .expect("run migrations on test database");
        let state = AppState {
            perms: Arc::new(
                Permissions::load(&app.pool)
                    .await
                    .expect("load permissions"),
            ),
            ..state
        };
        app.router = routes::router(state);
        app
    }

    /// A pooled connection to this test's database, for direct assertions.
    pub async fn client(&self) -> Object {
        self.pool.get().await.expect("test database connection")
    }

    pub async fn get(&self, path: &str, token: Option<&str>) -> TestResponse {
        self.request(Method::GET, path, token, None).await
    }

    pub async fn post_json(&self, path: &str, token: Option<&str>, body: &Value) -> TestResponse {
        self.request(Method::POST, path, token, Some(body)).await
    }

    pub async fn patch_json(&self, path: &str, token: Option<&str>, body: &Value) -> TestResponse {
        self.request(Method::PATCH, path, token, Some(body)).await
    }

    pub async fn put_json(&self, path: &str, token: Option<&str>, body: &Value) -> TestResponse {
        self.request(Method::PUT, path, token, Some(body)).await
    }

    pub async fn delete_json(
        &self,
        path: &str,
        token: Option<&str>,
        body: Option<&Value>,
    ) -> TestResponse {
        self.request(Method::DELETE, path, token, body).await
    }

    /// Registers a password user through the API and returns its token.
    pub async fn register(&self, display_name: &str, email: &str, password: &str) -> String {
        let res = self
            .post_json(
                "/api/v1/auth/register",
                None,
                &serde_json::json!({"display_name": display_name, "email": email, "password": password}),
            )
            .await;
        assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
        res.json["token"].as_str().expect("token").to_owned()
    }

    /// Inserts a Google-only user (no password identity) directly and returns its token.
    pub async fn google_user(&self, display_name: &str, email: &str) -> String {
        let client = self.client().await;
        let id: Uuid = client
            .query_one(
                "INSERT INTO users (email, display_name) VALUES ($1, $2) RETURNING id",
                &[&email, &display_name],
            )
            .await
            .expect("insert user")
            .get(0);
        client
            .execute(
                "INSERT INTO auth_identities (user_id, provider, provider_user_id)
                 VALUES ($1, 'google', $2)",
                &[&id, &format!("sub-{id}")],
            )
            .await
            .expect("insert google identity");
        backend::auth::jwt::issue_token(&self.config.jwt_secret, id, 1, self.config.jwt_expires_in)
            .expect("token")
    }

    /// Sends one request through the router. A JSON `body` sets the content type.
    pub async fn request(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&Value>,
    ) -> TestResponse {
        let mut builder = Request::builder().method(method).uri(path);
        if let Some(token) = token {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {token}"));
        }
        let body = match body {
            Some(json) => {
                builder = builder.header(header::CONTENT_TYPE, "application/json");
                Body::from(serde_json::to_vec(json).expect("serialize body"))
            }
            None => Body::empty(),
        };
        self.send(builder.body(body).expect("request")).await
    }

    /// Sends a hand-built request, for cases the helpers do not cover (raw bodies, headers).
    pub async fn send(&self, request: Request<Body>) -> TestResponse {
        let response = self
            .router
            .clone()
            .oneshot(request)
            .await
            .expect("router is infallible");
        let (parts, body) = response.into_parts();
        let bytes = body.collect().await.expect("response body").to_bytes();
        TestResponse {
            status: parts.status,
            headers: parts.headers,
            json: serde_json::from_slice(&bytes).unwrap_or(Value::Null),
            text: String::from_utf8_lossy(&bytes).into_owned(),
        }
    }
}

impl Drop for TestApp {
    /// Drops the test database. `Drop` cannot be async and may run on a runtime
    /// that is blocked right now (a current-thread `#[tokio::test]`), so the
    /// cleanup runs on its own thread with its own runtime and is joined here.
    /// `WITH (FORCE)` ends any connection still open, including ones the closed
    /// pool has not shut down yet.
    fn drop(&mut self) {
        self.pool.close();
        let admin_url = self.admin_url.clone();
        let db_name = self.db_name.clone();
        let result = std::thread::spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .map_err(|e| e.to_string())?;
            runtime.block_on(async {
                let admin = db::create_pool(&test_config(&admin_url)).map_err(|e| e.to_string())?;
                let client = admin.get().await.map_err(|e| e.to_string())?;
                client
                    .batch_execute(&format!("DROP DATABASE IF EXISTS {db_name} WITH (FORCE)"))
                    .await
                    .map_err(|e| e.to_string())?;
                drop(client);
                admin.close();
                Ok::<(), String>(())
            })
        })
        .join()
        .unwrap_or_else(|_| Err("cleanup thread panicked".to_owned()));

        if let Err(err) = result {
            let message = format!("could not drop test database {}: {err}", self.db_name);
            if std::thread::panicking() {
                eprintln!("{message}");
            } else {
                panic!("{message}");
            }
        }
    }
}

/// Development config pointing at `database_url`, with a fixed JWT secret and
/// no storage. Built with `from_lookup`, so `.env` and the process environment
/// (which may hold real credentials) are never read.
fn test_config(database_url: &str) -> Config {
    Config::from_lookup(|key| match key {
        "APP_ENV" => Some("development".to_owned()),
        "DATABASE_URL" => Some(database_url.to_owned()),
        "DATABASE_POOL_MAX" => Some("4".to_owned()),
        "JWT_SECRET" => Some(TEST_JWT_SECRET.to_owned()),
        _ => None,
    })
    .expect("test config")
}

/// Replaces the database name in a `postgres://` URL, keeping any query string.
fn with_database(url: &str, db_name: &str) -> String {
    let (base, query) = match url.split_once('?') {
        Some((base, query)) => (base, Some(query)),
        None => (url, None),
    };
    let authority_start = base
        .find("://")
        .map(|i| i + 3)
        .expect("TEST_DATABASE_URL must be a URL such as postgres://user@host:5432/postgres");
    let server = match base[authority_start..].find('/') {
        Some(i) => &base[..authority_start + i],
        None => base,
    };
    match query {
        Some(query) => format!("{server}/{db_name}?{query}"),
        None => format!("{server}/{db_name}"),
    }
}
