//! Transactions: the day list, detail and void. The response shapes are
//! shared with catat.

pub mod dto;
pub mod handlers;

use std::collections::HashMap;

use rust_decimal::prelude::ToPrimitive;
use time::OffsetDateTime;
use tokio_postgres::{GenericClient, Row};
use uuid::Uuid;

use crate::common::pagination::Cursor;
use crate::error::{AppError, AppResult, ErrorCode};
use dto::{DaySummary, ItemResponse, TransactionListItem, TransactionResponse};

/// Items named in a list row's `summary` before " +N lainnya".
const SUMMARY_ITEMS: usize = 3;

/// "Nasi goreng 2, Es teh manis 3", then " +N lainnya" past three items.
fn summary(items: &[(String, i64)]) -> String {
    let mut s = items
        .iter()
        .take(SUMMARY_ITEMS)
        .map(|(name, qty)| format!("{name} {qty}"))
        .collect::<Vec<_>>()
        .join(", ");
    if items.len() > SUMMARY_ITEMS {
        s.push_str(&format!(" +{} lainnya", items.len() - SUMMARY_ITEMS));
    }
    s
}

/// Columns `TransactionResponse::new` reads.
pub const TRANSACTION_COLUMNS: &str =
    "id, raw_text, total, status::text AS status, occurred_at, voided_at, void_reason";

/// Adds a transaction row's items (in `line_no` order) to build the response.
pub async fn with_items(client: &impl GenericClient, row: &Row) -> AppResult<TransactionResponse> {
    let items = client
        .query(
            "SELECT id, line_no, product_id, product_name, unit_price, quantity, line_total
               FROM transaction_items WHERE transaction_id = $1 ORDER BY line_no",
            &[&row.get::<_, i64>("id")],
        )
        .await?;
    let items = items.iter().map(ItemResponse::from).collect();
    Ok(TransactionResponse::new(row, items))
}

/// The user's transaction with its items; `None` if it is not theirs.
pub async fn find(
    client: &impl GenericClient,
    user_id: Uuid,
    id: i64,
) -> AppResult<Option<TransactionResponse>> {
    let row = client
        .query_opt(
            &format!(
                "SELECT {TRANSACTION_COLUMNS} FROM transactions WHERE user_id = $1 AND id = $2"
            ),
            &[&user_id, &id],
        )
        .await?;
    match row {
        Some(row) => Ok(Some(with_items(client, &row).await?)),
        None => Ok(None),
    }
}

/// Voids a completed transaction (the DB trigger restores stock) and returns
/// it. Not the user's: 404. Already voided: 409 `already_voided`.
pub async fn void(
    client: &impl GenericClient,
    user_id: Uuid,
    id: i64,
    reason: Option<&str>,
) -> AppResult<TransactionResponse> {
    let n = client
        .execute(
            "UPDATE transactions
                SET status = 'voided', voided_at = now(), void_reason = $3
              WHERE id = $1 AND user_id = $2 AND status = 'completed'",
            &[&id, &user_id, &reason],
        )
        .await?;
    match find(client, user_id, id).await? {
        None => Err(AppError::not_found()),
        Some(_) if n == 0 => Err(AppError::new(ErrorCode::AlreadyVoided)),
        Some(t) => Ok(t),
    }
}

/// One page of the user's transactions in `[start, end)`, newest first, after
/// `after` when given. Fetches `limit` rows (callers pass `limit + 1`), then
/// all their items in a second query: two queries however many rows.
pub async fn list_day(
    client: &impl GenericClient,
    user_id: Uuid,
    (start, end): (OffsetDateTime, OffsetDateTime),
    after: Option<Cursor>,
    limit: i64,
) -> AppResult<Vec<TransactionListItem>> {
    let rows = client
        .query(
            "SELECT id, occurred_at, total, status::text AS status
               FROM transactions
              WHERE user_id = $1 AND occurred_at >= $2 AND occurred_at < $3
                AND ($4::timestamptz IS NULL
                     OR (occurred_at, id) < ($4::timestamptz, $5::bigint))
              ORDER BY occurred_at DESC, id DESC
              LIMIT $6",
            &[
                &user_id,
                &start,
                &end,
                &after.map(|c| c.occurred_at),
                &after.map(|c| c.id),
                &limit,
            ],
        )
        .await?;
    let ids: Vec<i64> = rows.iter().map(|r| r.get("id")).collect();
    let item_rows = client
        .query(
            "SELECT transaction_id, product_name, quantity
               FROM transaction_items WHERE transaction_id = ANY($1)
              ORDER BY transaction_id, line_no",
            &[&ids],
        )
        .await?;
    let mut items: HashMap<i64, Vec<(String, i64)>> = HashMap::new();
    for r in &item_rows {
        let qty = r
            .get::<_, rust_decimal::Decimal>("quantity")
            .to_i64()
            .unwrap_or_default();
        items
            .entry(r.get("transaction_id"))
            .or_default()
            .push((r.get("product_name"), qty));
    }
    Ok(rows
        .iter()
        .map(|r| {
            let lines = items.get(&r.get::<_, i64>("id")).map_or(&[][..], |v| v);
            TransactionListItem::new(r, lines.len() as i64, summary(lines))
        })
        .collect())
}

/// Completed sales in `[start, end)`; voided ones are not counted.
pub async fn day_summary(
    client: &impl GenericClient,
    user_id: Uuid,
    date: time::Date,
    (start, end): (OffsetDateTime, OffsetDateTime),
) -> AppResult<DaySummary> {
    let row = client
        .query_one(
            "SELECT count(*) AS n, COALESCE(sum(total), 0)::bigint AS revenue
               FROM transactions
              WHERE user_id = $1 AND occurred_at >= $2 AND occurred_at < $3
                AND status = 'completed'",
            &[&user_id, &start, &end],
        )
        .await?;
    Ok(DaySummary::new(date, row.get("n"), row.get("revenue")))
}

#[cfg(test)]
mod tests {
    use super::summary;

    fn items(n: usize) -> Vec<(String, i64)> {
        (1..=n).map(|i| (format!("Produk {i}"), i as i64)).collect()
    }

    #[test]
    fn summary_lists_three_then_counts_the_rest() {
        assert_eq!(summary(&[]), "");
        assert_eq!(summary(&items(1)), "Produk 1 1");
        assert_eq!(summary(&items(3)), "Produk 1 1, Produk 2 2, Produk 3 3");
        assert_eq!(
            summary(&items(5)),
            "Produk 1 1, Produk 2 2, Produk 3 3 +2 lainnya"
        );
    }
}
