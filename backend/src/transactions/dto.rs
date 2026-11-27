//! Transaction JSON shapes. Quantities are whole numbers in v1, so they go
//! out as plain integers; money is whole rupiah.

use rust_decimal::prelude::ToPrimitive;
use serde::Serialize;
use time::{Date, OffsetDateTime};
use tokio_postgres::Row;

use crate::common::pagination::Cursor;
use crate::products::dto::rfc3339;

#[derive(Serialize)]
pub struct ItemResponse {
    pub id: i64,
    pub line_no: i16,
    /// `null` once the product was deleted.
    pub product_id: Option<i64>,
    pub product_name: String,
    pub unit_price: i64,
    pub quantity: i64,
    pub line_total: i64,
}

impl From<&Row> for ItemResponse {
    /// Columns: `id, line_no, product_id, product_name, unit_price, quantity, line_total`.
    fn from(r: &Row) -> Self {
        ItemResponse {
            id: r.get("id"),
            line_no: r.get("line_no"),
            product_id: r.get("product_id"),
            product_name: r.get("product_name"),
            unit_price: r.get("unit_price"),
            quantity: r
                .get::<_, rust_decimal::Decimal>("quantity")
                .to_i64()
                .unwrap_or_default(),
            line_total: r.get("line_total"),
        }
    }
}

#[derive(Serialize)]
pub struct TransactionResponse {
    pub id: i64,
    pub raw_text: String,
    pub total: i64,
    pub status: String,
    pub occurred_at: String,
    pub voided_at: Option<String>,
    pub void_reason: Option<String>,
    pub items: Vec<ItemResponse>,
}

impl TransactionResponse {
    /// `row` columns: `id, raw_text, total, status` (text), `occurred_at`,
    /// `voided_at`, `void_reason`.
    pub fn new(row: &Row, items: Vec<ItemResponse>) -> Self {
        TransactionResponse {
            id: row.get("id"),
            raw_text: row.get("raw_text"),
            total: row.get("total"),
            status: row.get("status"),
            occurred_at: rfc3339(row.get::<_, OffsetDateTime>("occurred_at")),
            voided_at: row
                .get::<_, Option<OffsetDateTime>>("voided_at")
                .map(rfc3339),
            void_reason: row.get("void_reason"),
            items,
        }
    }
}

/// One row of the day list.
#[derive(Serialize)]
pub struct TransactionListItem {
    pub id: i64,
    pub occurred_at: String,
    pub total: i64,
    pub status: String,
    pub item_count: i64,
    pub summary: String,
    #[serde(skip)]
    pub cursor: Cursor,
}

impl TransactionListItem {
    /// `row` columns: `id, occurred_at, total, status` (text).
    pub fn new(row: &Row, item_count: i64, summary: String) -> Self {
        let occurred_at: OffsetDateTime = row.get("occurred_at");
        let id: i64 = row.get("id");
        TransactionListItem {
            id,
            occurred_at: rfc3339(occurred_at),
            total: row.get("total"),
            status: row.get("status"),
            item_count,
            summary,
            cursor: Cursor { occurred_at, id },
        }
    }
}

/// Completed sales of the listed day.
#[derive(Serialize)]
pub struct DaySummary {
    pub date: String,
    pub transaction_count: i64,
    pub revenue: i64,
}

impl DaySummary {
    pub fn new(date: Date, transaction_count: i64, revenue: i64) -> Self {
        DaySummary {
            date: date.to_string(),
            transaction_count,
            revenue,
        }
    }
}
