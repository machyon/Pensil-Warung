//! `/analytics` endpoints.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::routing::get;
use serde::Deserialize;

use super::dto::{MonthRevenue, MonthSummary};
use super::{months, summary};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::ApiQuery;
use crate::common::time::resolve_month;
use crate::error::AppError;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/analytics/months", get(list_months))
        .route("/analytics/month", get(month_summary))
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
