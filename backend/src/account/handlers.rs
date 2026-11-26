//! `/me` endpoints. Every query is scoped to the authenticated user's id.
//! The PATCH routes return the updated user, the same shape as `GET /me`.

use axum::extract::State;
use axum::routing::{get, patch};
use axum::{Json, Router};
use serde::Deserialize;
use uuid::Uuid;

use crate::auth::extractor::AuthUser;
use crate::auth::user::{UserResponse, load_user};
use crate::common::extract::ApiJson;
use crate::error::{AppError, ErrorCode};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/me", get(me))
        .route("/me/username", patch(set_username))
}

async fn me(State(state): State<AppState>, user: AuthUser) -> Result<Json<UserResponse>, AppError> {
    let client = state.pool.get().await?;
    Ok(Json(load_user(&client, &state.perms, user.id).await?))
}

/// Runs one UPDATE of a single column on the caller's row, then returns the user.
/// `sql` takes `$1` = new value, `$2` = user id.
async fn update_and_load(
    state: &AppState,
    id: Uuid,
    sql: &str,
    value: &String,
) -> Result<Json<UserResponse>, AppError> {
    let client = state.pool.get().await?;
    if client.execute(sql, &[value, &id]).await? == 0 {
        return Err(AppError::new(ErrorCode::AccountGone));
    }
    Ok(Json(load_user(&client, &state.perms, id).await?))
}

#[derive(Deserialize)]
struct UsernameBody {
    username: String,
}

fn valid_username(s: &str) -> bool {
    (3..=30).contains(&s.len())
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
}

async fn set_username(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(body): ApiJson<UsernameBody>,
) -> Result<Json<UserResponse>, AppError> {
    if !valid_username(&body.username) {
        return Err(AppError::validation(
            ErrorCode::InvalidValue,
            "username",
            "Username 3-30 karakter: huruf kecil, angka, dan garis bawah.",
        ));
    }
    update_and_load(
        &state,
        user.id,
        "UPDATE users SET username = $1 WHERE id = $2",
        &body.username,
    )
    .await
}
