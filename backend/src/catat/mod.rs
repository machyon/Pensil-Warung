//! Catat: one Simpan saves a batch of typed lines (sales, restocks, product
//! creates and deletes) atomically. `dto` parses and validates the request,
//! `plan` resolves product names across the batch into an executable plan.

pub mod dto;
pub mod plan;

use rust_decimal::Decimal;
use tokio_postgres::GenericClient;
use uuid::Uuid;

use crate::common::names::name_key;
use crate::error::AppResult;

/// A product as the planner sees it. `name_key` is `common::names::name_key(name)`.
#[derive(Debug, Clone)]
pub struct ProductSnapshot {
    pub id: i64,
    pub name_key: String,
    pub price: i64,
    pub stock: Decimal,
    pub photo_key: Option<String>,
}

/// Loads all of the user's products and locks them (`FOR UPDATE`) until the
/// transaction ends, so the planned stock stays true while the plan executes.
/// Call it inside the batch transaction.
pub async fn load_products(
    client: &impl GenericClient,
    user_id: Uuid,
) -> AppResult<Vec<ProductSnapshot>> {
    let rows = client
        .query(
            "SELECT id, name, price, stock, photo_key FROM products
             WHERE user_id = $1 FOR UPDATE",
            &[&user_id],
        )
        .await?;
    Ok(rows
        .iter()
        .map(|r| ProductSnapshot {
            id: r.get("id"),
            name_key: name_key(&r.get::<_, String>("name")),
            price: r.get("price"),
            stock: r.get("stock"),
            photo_key: r.get("photo_key"),
        })
        .collect())
}
