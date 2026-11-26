//! Product JSON shapes.

use rust_decimal::prelude::ToPrimitive;
use serde::Serialize;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use super::Product;

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

fn rfc3339(t: OffsetDateTime) -> String {
    t.format(&Rfc3339).unwrap_or_default()
}

impl From<Product> for ProductResponse {
    fn from(p: Product) -> Self {
        ProductResponse {
            id: p.id,
            name: p.name,
            price: p.price,
            stock: p.stock.to_i64().unwrap_or_default(),
            photo_url: None,
            created_at: rfc3339(p.created_at),
            updated_at: rfc3339(p.updated_at),
        }
    }
}
