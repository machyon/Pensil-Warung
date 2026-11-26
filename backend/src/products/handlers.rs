//! `/products` endpoints. Every route needs `product.manage` and only sees
//! the caller's own products.

use axum::Json;
use axum::Router;
use axum::extract::{DefaultBodyLimit, Multipart, State};
use axum::routing::{get, post, put};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashSet;
use uuid::Uuid;

use super::dto::ProductResponse;
use super::{
    NewProduct, ProductPatch, create, delete, get as get_product, list, photo, set_photo_key,
    update,
};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::{ApiJson, ApiPath, ApiQuery};
use crate::common::names::name_key;
use crate::common::response::{Created, NoContent};
use crate::error::{AppError, ErrorCode};
use crate::state::AppState;

/// Upload limit for `PUT /products/{id}/photo`, multipart framing included.
const PHOTO_MAX_BYTES: usize = 5 * 1024 * 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/products", get(list_products).post(create_one))
        .route("/products/bulk", post(create_bulk))
        .route(
            "/products/{id}",
            get(get_one).patch(patch_one).delete(delete_one),
        )
        .route(
            "/products/{id}/photo",
            put(put_photo).layer(DefaultBodyLimit::max(PHOTO_MAX_BYTES)),
        )
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

/// All fields optional. `stock` is the new absolute stock (an integer).
#[derive(Deserialize)]
struct PatchBody {
    name: Option<String>,
    price: Option<i64>,
    stock: Option<i64>,
    note: Option<String>,
}

async fn patch_one(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(id): ApiPath<i64>,
    ApiJson(body): ApiJson<PatchBody>,
) -> Result<Json<ProductResponse>, AppError> {
    state.perms.require(&user, Perm::ProductManage)?;
    let patch = ProductPatch::new(
        body.name.as_deref(),
        body.price,
        body.stock,
        body.note.as_deref(),
    )?;
    let mut client = state.pool.get().await?;
    Ok(Json(
        update(&mut **client, user.id, id, &patch).await?.into(),
    ))
}

/// Hard delete: movements go with it, sale items keep their snapshots.
async fn delete_one(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(id): ApiPath<i64>,
) -> Result<NoContent, AppError> {
    state.perms.require(&user, Perm::ProductManage)?;
    let client = state.pool.get().await?;
    if !delete(&**client, user.id, id).await? {
        return Err(AppError::not_found());
    }
    // TODO(branch 05): delete the product's photo object.
    Ok(NoContent)
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

/// Reads the `photo` field of the multipart body. A body over the route's
/// limit surfaces here as 413.
async fn read_photo_field(mut multipart: Multipart) -> Result<Vec<u8>, AppError> {
    let invalid = |reason: &str| {
        AppError::new(ErrorCode::InvalidBody).with_details(json!({ "reason": reason }))
    };
    let to_error = |e: axum::extract::multipart::MultipartError| {
        if e.status() == axum::http::StatusCode::PAYLOAD_TOO_LARGE {
            AppError::new(ErrorCode::PayloadTooLarge)
        } else {
            invalid("multipart tidak valid")
        }
    };
    while let Some(field) = multipart.next_field().await.map_err(to_error)? {
        if field.name() == Some("photo") {
            return Ok(field.bytes().await.map_err(to_error)?.to_vec());
        }
    }
    Err(invalid("field photo wajib diisi"))
}

/// Replaces the product's photo: upload the new object, point the product at
/// it, then delete the old object (best effort). The upload is re-encoded to a
/// small JPEG, so the stored type never depends on the client.
async fn put_photo(
    State(state): State<AppState>,
    user: AuthUser,
    ApiPath(id): ApiPath<i64>,
    multipart: Multipart,
) -> Result<Json<ProductResponse>, AppError> {
    state.perms.require(&user, Perm::ProductManage)?;
    let storage = state
        .storage
        .clone()
        .ok_or_else(|| AppError::new(ErrorCode::StorageUnavailable))?;
    let client = state.pool.get().await?;
    get_product(&**client, user.id, id).await?;

    let raw = read_photo_field(multipart).await?;
    let jpeg = tokio::task::spawn_blocking(move || photo::prepare(&raw))
        .await
        .map_err(|_| AppError::internal())??;

    let key = format!("products/{}/{}/{}.jpg", user.id, id, Uuid::new_v4());
    storage
        .put(&key, jpeg, photo::CONTENT_TYPE)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "photo upload failed");
            AppError::new(ErrorCode::StorageUnavailable)
        })?;
    let old = match set_photo_key(&**client, user.id, id, &key).await {
        Ok(Some(old)) => old,
        failed => {
            if let Err(e) = storage.delete(&key).await {
                tracing::warn!(error = %e, key, "could not delete orphaned photo");
            }
            return Err(failed.err().unwrap_or_else(AppError::not_found));
        }
    };
    if let Some(old) = old
        && let Err(e) = storage.delete(&old).await
    {
        tracing::warn!(error = %e, key = old, "could not delete replaced photo");
    }
    Ok(Json(get_product(&**client, user.id, id).await?.into()))
}
