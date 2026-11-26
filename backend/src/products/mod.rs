//! Products and their stock. The functions here take a `GenericClient`, so
//! they run on a pooled client or inside a `Transaction` (catat calls them
//! from its own transaction). Every query is scoped by `user_id`.
//!
//! Stock is never UPDATEd here: the `products_initial_stock` trigger turns a
//! non-zero stock on INSERT into an `initial` movement, and `move_stock`
//! inserts movements for everything else.

pub mod dto;
pub mod handlers;

use rust_decimal::Decimal;
use time::OffsetDateTime;
use tokio_postgres::{GenericClient, Row};
use uuid::Uuid;

use crate::common::names::{name_key, normalize_product_name};
use crate::common::validate::non_negative_money;
use crate::error::{AppError, AppResult, ErrorCode};

const COLUMNS: &str = "id, name, price, stock, created_at, updated_at";

pub struct Product {
    pub id: i64,
    pub name: String,
    pub price: i64,
    pub stock: Decimal,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

impl From<&Row> for Product {
    fn from(row: &Row) -> Self {
        Product {
            id: row.get("id"),
            name: row.get("name"),
            price: row.get("price"),
            stock: row.get("stock"),
            created_at: row.get("created_at"),
            updated_at: row.get("updated_at"),
        }
    }
}

/// A validated new product: normalized name, price >= 0, stock >= 0.
pub struct NewProduct {
    pub name: String,
    pub price: i64,
    pub stock: Decimal,
}

impl NewProduct {
    pub fn new(name: &str, price: i64, stock: i64) -> AppResult<Self> {
        let name = normalize_product_name(name);
        if name.is_empty() || name.chars().count() > 60 {
            return Err(AppError::validation(
                ErrorCode::InvalidName,
                "name",
                "Nama produk 1-60 karakter.",
            ));
        }
        non_negative_money("price", price)?;
        if stock < 0 {
            return Err(AppError::validation(
                ErrorCode::InvalidValue,
                "stock",
                "stock tidak boleh negatif.",
            ));
        }
        Ok(NewProduct {
            name,
            price,
            stock: Decimal::from(stock),
        })
    }
}

/// Inserts a product. A duplicate name is 409 `name_taken` (mapped from the
/// unique index). A stock above 0 gets its `initial` movement from the trigger.
pub async fn create(
    client: &impl GenericClient,
    user_id: Uuid,
    new: &NewProduct,
) -> AppResult<Product> {
    let row = client
        .query_one(
            &format!(
                "INSERT INTO products (user_id, name, price, stock) VALUES ($1, $2, $3, $4)
                 RETURNING {COLUMNS}"
            ),
            &[&user_id, &new.name, &new.price, &new.stock],
        )
        .await?;
    Ok(Product::from(&row))
}

/// Deletes one of the user's products (movements cascade, sale snapshots stay).
/// Returns false when there is no such product.
pub async fn delete(client: &impl GenericClient, user_id: Uuid, id: i64) -> AppResult<bool> {
    let n = client
        .execute(
            "DELETE FROM products WHERE id = $1 AND user_id = $2",
            &[&id, &user_id],
        )
        .await?;
    Ok(n > 0)
}

/// Records a stock movement and returns the product's new stock. `delta` must
/// not be 0, and the caller must already know the product is the user's.
/// `reason` is a `stock_reason` value; going below 0 fails with 422 `stock_insufficient`.
pub async fn move_stock(
    client: &impl GenericClient,
    product_id: i64,
    delta: Decimal,
    reason: &str,
    note: Option<&str>,
) -> AppResult<Decimal> {
    let row = client
        .query_one(
            "INSERT INTO stock_movements (product_id, reason, delta, stock_after, note)
             VALUES ($1, $2::text::stock_reason, $3, 0, $4) RETURNING stock_after",
            &[&product_id, &reason, &delta, &note],
        )
        .await?;
    Ok(row.get(0))
}

/// Finds the user's product by name, ignoring case and extra spaces.
pub async fn find_by_name(
    client: &impl GenericClient,
    user_id: Uuid,
    name: &str,
) -> AppResult<Option<Product>> {
    let row = client
        .query_opt(
            &format!(
                "SELECT {COLUMNS} FROM products
                 WHERE user_id = $1 AND lower(btrim(name)) = $2"
            ),
            &[&user_id, &name_key(name)],
        )
        .await?;
    Ok(row.as_ref().map(Product::from))
}

pub async fn get(client: &impl GenericClient, user_id: Uuid, id: i64) -> AppResult<Product> {
    let row = client
        .query_opt(
            &format!("SELECT {COLUMNS} FROM products WHERE id = $1 AND user_id = $2"),
            &[&id, &user_id],
        )
        .await?
        .ok_or_else(AppError::not_found)?;
    Ok(Product::from(&row))
}

/// All of the user's products by name, optionally filtered by a case-insensitive
/// substring of the name (`%`, `_` and `\` in `q` match literally).
pub async fn list(
    client: &impl GenericClient,
    user_id: Uuid,
    q: Option<&str>,
) -> AppResult<Vec<Product>> {
    let pattern = q
        .map(normalize_product_name)
        .filter(|q| !q.is_empty())
        .map(|q| {
            let escaped = q
                .replace('\\', "\\\\")
                .replace('%', "\\%")
                .replace('_', "\\_");
            format!("%{escaped}%")
        });
    let rows = client
        .query(
            &format!(
                "SELECT {COLUMNS} FROM products
                 WHERE user_id = $1 AND ($2::text IS NULL OR name ILIKE $2)
                 ORDER BY lower(name), id"
            ),
            &[&user_id, &pattern],
        )
        .await?;
    Ok(rows.iter().map(Product::from).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_product_normalizes_and_validates() {
        let p = NewProduct::new("  Nasi   Goreng ", 15000, 3).unwrap();
        assert_eq!(p.name, "Nasi Goreng");
        assert_eq!(p.stock, Decimal::from(3));
        assert!(NewProduct::new("   ", 1, 0).is_err());
        assert!(NewProduct::new(&"a".repeat(61), 1, 0).is_err());
        assert!(NewProduct::new(&"a".repeat(60), 0, 0).is_ok());
        assert!(NewProduct::new("x", -1, 0).is_err());
        assert!(NewProduct::new("x", 1, -1).is_err());
    }
}
