//! `AuthUser`: the caller identified by the `Authorization: Bearer` token.

use axum::extract::FromRequestParts;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use uuid::Uuid;

use super::jwt::verify_token;
use crate::error::AppError;
use crate::state::AppState;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AuthUser {
    pub id: Uuid,
    pub role_id: i32,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(AppError::unauthorized)?;
        let claims = verify_token(&state.config.jwt_secret, token)?;
        Ok(AuthUser {
            id: claims.sub,
            role_id: claims.role,
        })
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use axum::Router;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::get;
    use time::Duration;
    use tower::ServiceExt;

    use super::*;
    use crate::auth::jwt::issue_token;
    use crate::config::Config;
    use crate::db;

    const SECRET: &str = "pensil-warung-test-jwt-secret-0123456789";

    fn app() -> Router {
        let config = Config::from_lookup(|key| match key {
            "DATABASE_URL" => Some("postgres://postgres@127.0.0.1:1/postgres".to_owned()),
            "JWT_SECRET" => Some(SECRET.to_owned()),
            _ => None,
        })
        .expect("config");
        let pool = db::create_pool(&config).expect("pool");
        let state = AppState {
            pool,
            config: Arc::new(config),
            perms: Arc::default(),
            google_keys: Arc::default(),
        };
        Router::new()
            .route(
                "/me",
                get(|user: AuthUser| async move { user.id.to_string() }),
            )
            .with_state(state)
    }

    async fn call(authorization: Option<String>) -> StatusCode {
        let mut req = Request::get("/me");
        if let Some(value) = authorization {
            req = req.header(AUTHORIZATION, value);
        }
        app()
            .oneshot(req.body(Body::empty()).unwrap())
            .await
            .unwrap()
            .status()
    }

    #[tokio::test]
    async fn valid_token_passes() {
        let token = issue_token(SECRET, Uuid::new_v4(), 1, Duration::days(7)).unwrap();
        assert_eq!(call(Some(format!("Bearer {token}"))).await, StatusCode::OK);
    }

    #[tokio::test]
    async fn missing_malformed_and_expired_are_401() {
        assert_eq!(call(None).await, StatusCode::UNAUTHORIZED);
        assert_eq!(
            call(Some("Bearer junk".into())).await,
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            call(Some("Basic abc".into())).await,
            StatusCode::UNAUTHORIZED
        );
        let old = issue_token(SECRET, Uuid::new_v4(), 1, Duration::seconds(-5)).unwrap();
        assert_eq!(
            call(Some(format!("Bearer {old}"))).await,
            StatusCode::UNAUTHORIZED
        );
    }
}
