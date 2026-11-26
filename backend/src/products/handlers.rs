//! `/products` endpoints. Every route needs `product.manage` and only sees
//! the caller's own products.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::routing::get;
use serde::{Deserialize, Serialize};

use super::dto::ProductResponse;
use super::{get as get_product, list};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::{ApiPath, ApiQuery};
use crate::error::AppError;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/products", get(list_products))
        .route("/products/{id}", get(get_one))
}

#[derive(Deserialize)]
struct ListQuery {
    q: Option<String>,
}

#[derive(Serialize)]
struct ListResponse {
    items: Vec<ProductResponse>,
    count: usize,
}

async fn list_products(
    State(state): State<AppState>,
    user: AuthUser,
    ApiQuery(query): ApiQuery<ListQuery>,
) -> Result<Json<ListResponse>, AppError> {
    state.perms.require(&user, Perm::ProductManage)?;
    let client = state.pool.get().await?;
    let items: Vec<ProductResponse> = list(&**client, user.id, query.q.as_deref())
        .await?
        .into_iter()
        .map(Into::into)
        .collect();
    Ok(Json(ListResponse {
        count: items.len(),
        items,
    }))
}

async fn get_one(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(id): ApiPath<i64>,
) -> Result<Json<ProductResponse>, AppError> {
    state.perms.require(&user, Perm::ProductManage)?;
    let client = state.pool.get().await?;
    Ok(Json(get_product(&**client, user.id, id).await?.into()))
}
