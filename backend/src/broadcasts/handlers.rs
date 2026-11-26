//! `/broadcasts` endpoints.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::routing::get;
use serde::Deserialize;

use super::dto::{BroadcastItem, BroadcastWithBody, BroadcasterDetail, BroadcasterList};
use super::{NewBroadcast, broadcaster_list, create, detail as find, feed, feed_one};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::{ApiJson, ApiPath, ApiQuery};
use crate::common::pagination::{Cursor, clamp_limit};
use crate::common::response::Created;
use crate::error::AppError;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/broadcasts", get(list))
        .route("/broadcasts/{id}", get(detail))
        .route(
            "/broadcaster/broadcasts",
            get(broadcaster_home).post(create_one),
        )
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

#[derive(Deserialize)]
struct NewBroadcastBody {
    category: String,
    title: String,
    summary: String,
    body: Option<String>,
    /// RFC 3339 time to schedule, or `null` (or missing) to send now.
    send_at: Option<String>,
}

async fn create_one(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(b): ApiJson<NewBroadcastBody>,
) -> Result<Created<BroadcasterDetail>, AppError> {
    state.perms.require(&user, Perm::BroadcastCreate)?;
    let new = NewBroadcast::new(
        &b.category,
        &b.title,
        &b.summary,
        b.body.as_deref(),
        b.send_at.as_deref(),
    )?;
    let client = state.pool.get().await?;
    let id = create(&**client, user.id, &new).await?;
    let made = find(&**client, id).await?.ok_or_else(AppError::internal)?;
    Ok(Created(made))
}
