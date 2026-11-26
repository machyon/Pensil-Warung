//! `/broadcasts` endpoints.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::routing::get;

use super::dto::{BroadcastItem, BroadcastWithBody};
use super::{feed, feed_one};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::ApiPath;
use crate::error::AppError;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/broadcasts", get(list))
        .route("/broadcasts/{id}", get(detail))
}

async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<BroadcastItem>>, AppError> {
    state.perms.require(&user, Perm::BroadcastRead)?;
    let client = state.pool.get().await?;
    Ok(Json(feed(&**client).await?))
}

async fn detail(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(id): ApiPath<i32>,
) -> Result<Json<BroadcastWithBody>, AppError> {
    state.perms.require(&user, Perm::BroadcastRead)?;
    let client = state.pool.get().await?;
    let found = feed_one(&**client, id).await?;
    Ok(Json(found.ok_or_else(AppError::not_found)?))
}
