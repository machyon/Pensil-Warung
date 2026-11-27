//! Product JSON shapes.

use std::time::Duration;

use rust_decimal::prelude::ToPrimitive;
use serde::Serialize;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use super::{Movement, Product};
use crate::state::AppState;

/// Stock is a whole number in v1, so it goes out as a plain integer.
#[derive(Serialize)]
pub struct ProductResponse {
    pub id: i64,
    name: String,
    price: i64,
    stock: i64,
    photo_url: Option<String>,
    created_at: String,
    updated_at: String,
}

pub fn rfc3339(t: OffsetDateTime) -> String {
    t.format(&Rfc3339).unwrap_or_default()
}

impl ProductResponse {
    fn new(p: Product, photo_url: Option<String>) -> Self {
        ProductResponse {
            id: p.id,
            name: p.name,
            price: p.price,
            stock: p.stock.to_i64().unwrap_or_default(),
            photo_url,
            created_at: rfc3339(p.created_at),
            updated_at: rfc3339(p.updated_at),
        }
    }
}

/// Turns products into responses. `photo_url` is a fresh presigned GET when
/// there is storage and a photo; a signing failure is logged and gives null.
pub async fn respond(state: &AppState, products: Vec<Product>) -> Vec<ProductResponse> {
    let mut out = Vec::with_capacity(products.len());
    for p in products {
        let url = match (&state.storage, &p.photo_key) {
            (Some(storage), Some(key)) => {
                // Storage is set but its config is not only in tests: use the config default.
                let ttl = state
                    .config
                    .storage
                    .as_ref()
                    .map_or(Duration::from_secs(3600), |c| c.image_url_ttl);
                match storage.presign_get(key, ttl).await {
                    Ok(url) => Some(url),
                    Err(e) => {
                        tracing::error!(error = %e, product_id = p.id, "could not presign photo url");
                        None
                    }
                }
            }
            _ => None,
        };
        out.push(ProductResponse::new(p, url));
    }
    out
}

pub async fn respond_one(state: &AppState, product: Product) -> ProductResponse {
    respond(state, vec![product]).await.remove(0)
}

/// Quantities are whole numbers in v1, so they go out as plain integers.
#[derive(Serialize)]
pub struct MovementResponse {
    id: i64,
    reason: String,
    delta: i64,
    stock_after: i64,
    note: Option<String>,
    created_at: String,
    transaction_id: Option<i64>,
}

impl From<Movement> for MovementResponse {
    fn from(m: Movement) -> Self {
        MovementResponse {
            id: m.id,
            reason: m.reason,
            delta: m.delta.to_i64().unwrap_or_default(),
            stock_after: m.stock_after.to_i64().unwrap_or_default(),
            note: m.note,
            created_at: rfc3339(m.created_at),
            transaction_id: m.transaction_id,
        }
    }
}
