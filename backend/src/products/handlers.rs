//! `/products` endpoints. Every route needs `product.manage` and only sees
//! the caller's own products.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::routing::{get, post};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashSet;

use super::dto::ProductResponse;
use super::{NewProduct, create, get as get_product, list};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::{ApiJson, ApiPath, ApiQuery};
use crate::common::names::name_key;
use crate::common::response::Created;
use crate::error::{AppError, ErrorCode};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/products", get(list_products).post(create_one))
        .route("/products/bulk", post(create_bulk))
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

/// `stock` is an integer: a decimal such as 1.5 is rejected as `invalid_body`.
#[derive(Deserialize)]
struct NewProductBody {
    name: String,
    price: i64,
    stock: i64,
}

impl NewProductBody {
    fn validate(&self) -> Result<NewProduct, AppError> {
        NewProduct::new(&self.name, self.price, self.stock)
    }
}

async fn create_one(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(body): ApiJson<NewProductBody>,
) -> Result<Created<ProductResponse>, AppError> {
    state.perms.require(&user, Perm::ProductManage)?;
    let new = body.validate()?;
    let client = state.pool.get().await?;
    Ok(Created(create(&**client, user.id, &new).await?.into()))
}

#[derive(Deserialize)]
struct BulkBody {
    items: Vec<NewProductBody>,
}

#[derive(Serialize)]
struct BulkResponse {
    items: Vec<ProductResponse>,
}

/// All or nothing. A duplicate is 409 `name_taken` with `details.index`: the
/// later item for a clash inside the batch, or the item that hit an existing product.
async fn create_bulk(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(body): ApiJson<BulkBody>,
) -> Result<Created<BulkResponse>, AppError> {
    state.perms.require(&user, Perm::ProductManage)?;
    if !(1..=50).contains(&body.items.len()) {
        return Err(AppError::validation(
            ErrorCode::InvalidValue,
            "items",
            "items harus 1-50 produk.",
        ));
    }
    let new: Vec<NewProduct> = body
        .items
        .iter()
        .map(NewProductBody::validate)
        .collect::<Result<_, _>>()?;
    let mut seen = HashSet::new();
    for (index, item) in new.iter().enumerate() {
        if !seen.insert(name_key(&item.name)) {
            return Err(name_taken(index));
        }
    }
    let mut client = state.pool.get().await?;
    let tx = client.transaction().await?;
    let mut items = Vec::with_capacity(new.len());
    for (index, item) in new.iter().enumerate() {
        match create(&*tx, user.id, item).await {
            Ok(p) => items.push(p.into()),
            Err(e) if e.code() == ErrorCode::NameTaken => return Err(name_taken(index)),
            Err(e) => return Err(e),
        }
    }
    tx.commit().await?;
    Ok(Created(BulkResponse { items }))
}

fn name_taken(index: usize) -> AppError {
    AppError::new(ErrorCode::NameTaken).with_details(json!({ "index": index }))
}
