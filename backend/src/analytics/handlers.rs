//! `/analytics` endpoints.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::routing::get;

use super::dto::MonthRevenue;
use super::months;
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::error::AppError;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new().route("/analytics/months", get(list_months))
}

async fn list_months(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<MonthRevenue>>, AppError> {
    state.perms.require(&user, Perm::AnalyticsRead)?;
    let client = state.pool.get().await?;
    Ok(Json(months(&**client, user.id).await?))
}
