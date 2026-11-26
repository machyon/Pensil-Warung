//! `/me` endpoints. Every query is scoped to the authenticated user's id.
//! The PATCH routes return the updated user, the same shape as `GET /me`.

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};

use crate::auth::extractor::AuthUser;
use crate::auth::user::{UserResponse, load_user};
use crate::error::AppError;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new().route("/me", get(me))
}

async fn me(State(state): State<AppState>, user: AuthUser) -> Result<Json<UserResponse>, AppError> {
    let client = state.pool.get().await?;
    Ok(Json(load_user(&client, &state.perms, user.id).await?))
}
