//! `/transactions` endpoints.

use axum::Json;
use axum::Router;
use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::{get, post};
use serde::{Deserialize, Serialize};
use serde_json::json;
use time::Date;
use time::macros::format_description;

use super::dto::{DaySummary, TransactionListItem, TransactionResponse};
use super::revise::{ReviseRequest, revise};
use super::{day_summary, find, list_day, void};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::{ApiJson, ApiPath, ApiQuery};
use crate::common::pagination::{Cursor, Page, clamp_limit};
use crate::common::time::{today_wib, wib_day_bounds};
use crate::common::validate::max_len;
use crate::error::{AppError, ErrorCode};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/transactions", get(list))
        .route("/transactions/{id}", get(detail))
        .route("/transactions/{id}/void", post(void_one))
        .route("/transactions/{id}/revise", post(revise_one))
}

#[derive(Deserialize)]
struct ListQuery {
    date: Option<String>,
    cursor: Option<String>,
    limit: Option<i64>,
}

#[derive(Serialize)]
struct ListResponse {
    #[serde(flatten)]
    page: Page<TransactionListItem>,
    /// Only on the first page (no `cursor`).
    day: Option<DaySummary>,
}

fn parse_date(s: &str) -> Result<Date, AppError> {
    Date::parse(s, format_description!("[year]-[month]-[day]")).map_err(|_| {
        AppError::validation(
            ErrorCode::InvalidValue,
            "date",
            "Tanggal harus berformat YYYY-MM-DD.",
        )
    })
}

async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    ApiQuery(q): ApiQuery<ListQuery>,
) -> Result<Json<ListResponse>, AppError> {
    state.perms.require(&user, Perm::TransactionRead)?;
    let date = q
        .date
        .as_deref()
        .map(parse_date)
        .transpose()?
        .unwrap_or_else(today_wib);
    let after = q.cursor.as_deref().map(Cursor::decode).transpose()?;
    let limit = clamp_limit(q.limit);
    let bounds = wib_day_bounds(date);

    let client = state.pool.get().await?;
    let rows = list_day(&**client, user.id, bounds, after, limit + 1).await?;
    let day = match after {
        None => Some(day_summary(&**client, user.id, date, bounds).await?),
        Some(_) => None,
    };
    let page = Page::new(rows, limit, |t| t.cursor);
    Ok(Json(ListResponse { page, day }))
}

async fn detail(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(id): ApiPath<i64>,
) -> Result<Json<TransactionResponse>, AppError> {
    state.perms.require(&user, Perm::TransactionRead)?;
    let client = state.pool.get().await?;
    let t = find(&**client, user.id, id).await?;
    t.map(Json).ok_or_else(AppError::not_found)
}

#[derive(Deserialize)]
struct VoidRequest {
    reason: Option<String>,
}

async fn void_one(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(id): ApiPath<i64>,
    body: Bytes,
) -> Result<Json<TransactionResponse>, AppError> {
    state.perms.require(&user, Perm::TransactionVoid)?;
    // An empty body means no reason; anything else must be valid JSON.
    let req: VoidRequest = if body.is_empty() {
        VoidRequest { reason: None }
    } else {
        serde_json::from_slice(&body).map_err(|e| {
            AppError::new(ErrorCode::InvalidBody).with_details(json!({ "reason": e.to_string() }))
        })?
    };
    let reason = req
        .reason
        .as_deref()
        .map(str::trim)
        .filter(|r| !r.is_empty());
    if let Some(r) = reason {
        max_len("reason", r, 200)?;
    }
    let client = state.pool.get().await?;
    Ok(Json(void(&**client, user.id, id, reason).await?))
}

async fn revise_one(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(id): ApiPath<i64>,
    ApiJson(req): ApiJson<ReviseRequest>,
) -> Result<(StatusCode, Json<TransactionResponse>), AppError> {
    state.perms.require(&user, Perm::TransactionCreate)?;
    state.perms.require(&user, Perm::TransactionVoid)?;
    let (created, t) = revise(&state.pool, user.id, id, req).await?;
    let status = if created {
        StatusCode::CREATED
    } else {
        StatusCode::OK
    };
    Ok((status, Json(t)))
}
