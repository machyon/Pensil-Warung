//! Products and their stock. The functions here take a `GenericClient`, so
//! they run on a pooled client or inside a `Transaction` (catat calls them
//! from its own transaction). Every query is scoped by `user_id`.
//!
//! Stock is never UPDATEd here: the `products_initial_stock` trigger turns a
//! non-zero stock on INSERT into an `initial` movement, and `move_stock`
//! inserts movements for everything else.

pub mod dto;
pub mod handlers;
pub mod photo;

use rust_decimal::Decimal;
use time::OffsetDateTime;
use tokio_postgres::{GenericClient, Row};
use uuid::Uuid;

use crate::common::names::{name_key, normalize_product_name};
use crate::common::validate::{max_len, non_negative_money};
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

/// A validated PATCH: at least one field, normalized name, `note` only with `stock`.
pub struct ProductPatch {
    name: Option<String>,
    price: Option<i64>,
    stock: Option<Decimal>,
    note: Option<String>,
}

impl ProductPatch {
    pub fn new(
        name: Option<&str>,
        price: Option<i64>,
        stock: Option<i64>,
        note: Option<&str>,
    ) -> AppResult<Self> {
        if name.is_none() && price.is_none() && stock.is_none() && note.is_none() {
            return Err(AppError::new(ErrorCode::NothingToUpdate));
        }
        if note.is_some() && stock.is_none() {
            return Err(AppError::validation(
                ErrorCode::InvalidValue,
                "note",
                "note hanya bisa dikirim bersama stock.",
            ));
        }
        // Reuse the create rules; the placeholders for omitted fields always pass.
        let checked = NewProduct::new(name.unwrap_or("x"), price.unwrap_or(0), stock.unwrap_or(0))?;
        let note = note.map(str::trim).filter(|n| !n.is_empty());
        if let Some(n) = note {
            max_len("note", n, 200)?;
        }
        Ok(ProductPatch {
            name: name.map(|_| checked.name),
            price,
            stock: stock.map(|_| checked.stock),
            note: note.map(str::to_owned),
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

/// Changes a product's name, price and/or stock in one transaction. `stock` is
/// the new absolute stock: the difference becomes a `restock` or `adjustment`
/// movement (none when unchanged, so `note` is dropped). 404 if not the user's.
pub async fn update(
    client: &mut impl GenericClient,
    user_id: Uuid,
    id: i64,
    patch: &ProductPatch,
) -> AppResult<Product> {
    let tx = client.transaction().await?;
    let row = tx
        .query_opt(
            "SELECT stock FROM products WHERE id = $1 AND user_id = $2 FOR UPDATE",
            &[&id, &user_id],
        )
        .await?
        .ok_or_else(AppError::not_found)?;
    let current: Decimal = row.get(0);
    tx.execute(
        "UPDATE products SET name = COALESCE($3, name), price = COALESCE($4, price)
         WHERE id = $1 AND user_id = $2",
        &[&id, &user_id, &patch.name, &patch.price],
    )
    .await?;
    if let Some(stock) = patch.stock {
        let delta = stock - current;
        if !delta.is_zero() {
            let reason = if delta > Decimal::ZERO {
                "restock"
            } else {
                "adjustment"
            };
            move_stock(&tx, id, delta, reason, patch.note.as_deref()).await?;
        }
    }
    let product = get(&tx, user_id, id).await?;
    tx.commit().await?;
    Ok(product)
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

/// Points the user's product at a new photo object and returns the previous
/// key: `None` when there is no such product, `Some(None)` when it had no photo.
pub async fn set_photo_key(
    client: &impl GenericClient,
    user_id: Uuid,
    id: i64,
    key: &str,
) -> AppResult<Option<Option<String>>> {
    let row = client
        .query_opt(
            "UPDATE products p SET photo_key = $3 FROM
               (SELECT photo_key FROM products WHERE id = $1 AND user_id = $2 FOR UPDATE) old
             WHERE p.id = $1 AND p.user_id = $2 RETURNING old.photo_key",
            &[&id, &user_id, &key],
        )
        .await?;
    Ok(row.map(|r| r.get(0)))
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

    #[test]
    fn patch_rules() {
        assert!(ProductPatch::new(None, None, None, None).is_err());
        assert!(ProductPatch::new(None, None, None, Some("n")).is_err());
        assert!(ProductPatch::new(Some(" "), None, None, None).is_err());
        assert!(ProductPatch::new(None, Some(-1), None, None).is_err());
        assert!(ProductPatch::new(None, None, Some(-1), None).is_err());
        assert!(ProductPatch::new(None, None, Some(1), Some(&"a".repeat(201))).is_err());
        let p = ProductPatch::new(Some(" A  b "), None, Some(2), Some(" ok ")).unwrap();
        assert_eq!(p.name.as_deref(), Some("A b"));
        assert_eq!(p.note.as_deref(), Some("ok"));
    }
}
