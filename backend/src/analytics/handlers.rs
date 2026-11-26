//! `/analytics` endpoints.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::routing::get;
use serde::Deserialize;

use super::dto::{DayItems, DaySales, MonthRevenue, MonthSummary};
use super::{day_items, days, months, summary};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::{ApiPath, ApiQuery};
use crate::common::pagination::{Page, clamp_limit, decode_day, encode_day};
use crate::common::time::{resolve_day, resolve_month};
use crate::error::AppError;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/analytics/months", get(list_months))
        .route("/analytics/month", get(month_summary))
        .route("/analytics/month/days", get(month_days))
        .route("/analytics/days/{date}/items", get(day_items_list))
}

#[derive(Deserialize)]
struct MonthQuery {
    month: Option<String>,
}

async fn month_summary(
    State(state): State<AppState>,
    user: AuthUser,
    ApiQuery(q): ApiQuery<MonthQuery>,
) -> Result<Json<MonthSummary>, AppError> {
    state.perms.require(&user, Perm::AnalyticsRead)?;
    let month = resolve_month(q.month.as_deref())?;
    let client = state.pool.get().await?;
    Ok(Json(summary(&**client, user.id, month).await?))
}

async fn list_months(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<MonthRevenue>>, AppError> {
    state.perms.require(&user, Perm::AnalyticsRead)?;
    let client = state.pool.get().await?;
    Ok(Json(months(&**client, user.id).await?))
}

#[derive(Deserialize)]
struct DaysQuery {
    month: Option<String>,
    cursor: Option<String>,
    limit: Option<i64>,
}

async fn month_days(
    State(state): State<AppState>,
    user: AuthUser,
    ApiQuery(q): ApiQuery<DaysQuery>,
) -> Result<Json<Page<DaySales>>, AppError> {
    state.perms.require(&user, Perm::AnalyticsRead)?;
    let month = resolve_month(q.month.as_deref())?;
    let before = q.cursor.as_deref().map(decode_day).transpose()?;
    let limit = clamp_limit(q.limit);
    let client = state.pool.get().await?;
    let rows = days(&**client, user.id, month, before, limit + 1).await?;
    Ok(Json(Page::with_key(rows, limit, |d| encode_day(&d.day))))
}

async fn day_items_list(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(date): ApiPath<String>,
) -> Result<Json<DayItems>, AppError> {
    state.perms.require(&user, Perm::AnalyticsRead)?;
    let day = resolve_day(&date)?;
    let client = state.pool.get().await?;
    Ok(Json(day_items(&**client, user.id, day).await?))
}
