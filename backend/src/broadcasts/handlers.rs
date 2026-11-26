//! `/broadcasts` endpoints.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::routing::get;
use serde::Deserialize;

use super::dto::{BroadcastItem, BroadcastWithBody, BroadcasterList};
use super::{broadcaster_list, feed, feed_one};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::{ApiPath, ApiQuery};
use crate::common::pagination::{Cursor, clamp_limit};
use crate::error::AppError;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/broadcasts", get(list))
        .route("/broadcasts/{id}", get(detail))
        .route("/broadcaster/broadcasts", get(broadcaster_home))
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

#[derive(Deserialize)]
struct HomeQuery {
    cursor: Option<String>,
    limit: Option<i64>,
}

async fn broadcaster_home(
    State(state): State<AppState>,
    user: AuthUser,
    ApiQuery(q): ApiQuery<HomeQuery>,
) -> Result<Json<BroadcasterList>, AppError> {
    state.perms.require(&user, Perm::BroadcastCreate)?;
    let before = q.cursor.as_deref().map(Cursor::decode).transpose()?;
    let client = state.pool.get().await?;
    Ok(Json(
        broadcaster_list(&**client, before, clamp_limit(q.limit)).await?,
    ))
}
