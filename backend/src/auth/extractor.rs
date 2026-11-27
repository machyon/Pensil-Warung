//! `AuthUser`: the caller identified by the `Authorization: Bearer` token.

use axum::extract::FromRequestParts;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use uuid::Uuid;

use super::jwt::verify_token;
use crate::error::{AppError, ErrorCode};
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
        // One PK lookup per request: a missing user is a deleted account,
        // a different version means the token was revoked.
        let client = state.pool.get().await?;
        let row = client
            .query_opt(
                "SELECT token_version FROM users WHERE id = $1",
                &[&claims.sub],
            )
            .await?
            .ok_or_else(|| AppError::new(ErrorCode::AccountGone))?;
        if row.get::<_, i32>(0) != claims.ver {
            return Err(AppError::unauthorized());
        }
        Ok(AuthUser {
            id: claims.sub,
            role_id: claims.role,
        })
    }
}
