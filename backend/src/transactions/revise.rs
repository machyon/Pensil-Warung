//! `POST /transactions/{id}/revise`: voids a sale and inserts its replacement
//! in one DB transaction. Stock only moves through the triggers (the void
//! restores it, the new items take it).

use std::collections::{HashMap, HashSet};

use deadpool_postgres::Pool;
use rust_decimal::Decimal;
use rust_decimal::prelude::ToPrimitive;
use serde::Deserialize;
use serde_json::{Number, json};
use time::OffsetDateTime;
use tokio_postgres::GenericClient;
use uuid::Uuid;

use super::dto::TransactionResponse;
use super::void;
use crate::catat::dto::{LineError, lines_invalid, quantity_of};
use crate::catat::exec::{find_by_client_uuid, insert_snapshot_item, insert_transaction};
use crate::common::money::line_total;
use crate::error::{AppError, AppResult, ErrorCode};

const MAX_ITEMS: usize = 200;

#[derive(Deserialize)]
pub struct ReviseRequest {
    client_uuid: Uuid,
    items: Vec<ReviseLine>,
}

/// `{item_id, quantity}` keeps an old item, `{product_id, quantity}` adds one.
/// The quantity is a JSON number so `2.5` is a line error, not a 400.
#[derive(Deserialize)]
struct ReviseLine {
    item_id: Option<i64>,
    product_id: Option<i64>,
    quantity: Number,
}

/// A line of the new sale, resolved to its snapshot.
struct NewLine {
    product_id: Option<i64>,
    name: String,
    unit_price: i64,
    quantity: Decimal,
}

struct OldItem {
    product_id: Option<i64>,
    name: String,
    unit_price: i64,
    quantity: Decimal,
}

fn body_error(reason: &str) -> AppError {
    AppError::new(ErrorCode::InvalidBody)
        .with_status(axum::http::StatusCode::UNPROCESSABLE_ENTITY)
        .with_details(json!({ "reason": reason }))
}

/// Revises the user's transaction `id`. Returns whether a new row was created
/// (`false` is a retry that replays the stored one).
pub async fn revise(
    pool: &Pool,
    user_id: Uuid,
    id: i64,
    req: ReviseRequest,
) -> AppResult<(bool, TransactionResponse)> {
    if req.items.is_empty() || req.items.len() > MAX_ITEMS {
        return Err(body_error("items harus berisi 1-200 item."));
    }
    if req
        .items
        .iter()
        .any(|l| l.item_id.is_some() == l.product_id.is_some())
    {
        return Err(body_error(
            "Setiap item harus punya salah satu dari item_id atau product_id.",
        ));
    }
    let mut client = pool.get().await?;
    if let Some(t) = find_by_client_uuid(&**client, user_id, req.client_uuid).await? {
        return Ok((false, t));
    }
    let tx = client.transaction().await?;
    match run(&*tx, user_id, id, &req).await {
        Ok(t) => {
            tx.commit().await?;
            Ok((true, t))
        }
        Err(e) => {
            drop(tx);
            // A concurrent retry may have won the lock and stored the sale.
            match find_by_client_uuid(&**client, user_id, req.client_uuid).await? {
                Some(t) => Ok((false, t)),
                None => Err(e),
            }
        }
    }
}

async fn run(
    tx: &impl GenericClient,
    user_id: Uuid,
    id: i64,
    req: &ReviseRequest,
) -> AppResult<TransactionResponse> {
    let old = tx
        .query_opt(
            "SELECT occurred_at, status::text AS status FROM transactions
              WHERE id = $1 AND user_id = $2 FOR UPDATE",
            &[&id, &user_id],
        )
        .await?
        .ok_or_else(AppError::not_found)?;
    if old.get::<_, String>("status") != "completed" {
        return Err(AppError::new(ErrorCode::AlreadyVoided));
    }
    let occurred_at: OffsetDateTime = old.get("occurred_at");

    let old_items: HashMap<i64, OldItem> = tx
        .query(
            "SELECT id, product_id, product_name, unit_price, quantity
               FROM transaction_items WHERE transaction_id = $1",
            &[&id],
        )
        .await?
        .iter()
        .map(|r| {
            (
                r.get("id"),
                OldItem {
                    product_id: r.get("product_id"),
                    name: r.get("product_name"),
                    unit_price: r.get("unit_price"),
                    quantity: r.get("quantity"),
                },
            )
        })
        .collect();

    // Lock every product the old or new sale touches, in id order.
    let mut product_ids: Vec<i64> = old_items
        .values()
        .filter_map(|i| i.product_id)
        .chain(req.items.iter().filter_map(|l| l.product_id))
        .collect();
    product_ids.sort_unstable();
    product_ids.dedup();
    let products: HashMap<i64, (String, i64, Decimal)> = tx
        .query(
            "SELECT id, name, price, stock FROM products
              WHERE user_id = $1 AND id = ANY($2) ORDER BY id FOR UPDATE",
            &[&user_id, &product_ids],
        )
        .await?
        .iter()
        .map(|r| (r.get("id"), (r.get("name"), r.get("price"), r.get("stock"))))
        .collect();

    // Resolve each line; collect every problem before failing.
    let mut errors: Vec<LineError> = Vec::new();
    let mut lines: Vec<(u32, NewLine)> = Vec::new();
    let mut seen: HashSet<i64> = HashSet::new();
    for (i, l) in req.items.iter().enumerate() {
        let line_no = i as u32 + 1;
        let quantity = quantity_of(line_no, &l.quantity);
        let snapshot = match (l.item_id, l.product_id) {
            (Some(item_id), _) => match old_items.get(&item_id) {
                Some(o) if seen.insert(item_id) => Ok((o.product_id, o.name.clone(), o.unit_price)),
                _ => Err(LineError::new(
                    line_no,
                    ErrorCode::ItemNotFound,
                    "Item bukan bagian dari transaksi ini.",
                )),
            },
            (None, Some(pid)) => match products.get(&pid) {
                Some((name, price, _)) => Ok((Some(pid), name.clone(), *price)),
                None => Err(LineError::new(
                    line_no,
                    ErrorCode::ProductNotFound,
                    "Produk tidak ditemukan.",
                )),
            },
            (None, None) => unreachable!("checked in revise"),
        };
        match (snapshot, quantity) {
            (Ok((product_id, name, unit_price)), Ok(quantity)) => lines.push((
                line_no,
                NewLine {
                    product_id,
                    name,
                    unit_price,
                    quantity,
                },
            )),
            (s, q) => {
                errors.extend(s.err());
                errors.extend(q.err());
            }
        }
    }

    // Stock as if the old sale were voided first: stock + old qty - new qty.
    let mut left: HashMap<i64, Decimal> = products
        .iter()
        .map(|(pid, (_, _, stock))| (*pid, *stock))
        .collect();
    for o in old_items.values() {
        if let Some(pid) = o.product_id {
            *left.entry(pid).or_default() += o.quantity;
        }
    }
    for (_, l) in &lines {
        if let Some(pid) = l.product_id {
            *left.entry(pid).or_default() -= l.quantity;
        }
    }
    for (line_no, l) in &lines {
        if l.product_id.is_some_and(|pid| left[&pid] < Decimal::ZERO) {
            errors.push(LineError::new(
                *line_no,
                ErrorCode::StockInsufficient,
                "Stok tidak cukup.",
            ));
        }
    }
    if !errors.is_empty() {
        errors.sort_by_key(|e| e.line_no);
        return Err(lines_invalid(&errors));
    }

    // Only kept items with unchanged quantities (order aside): nothing to do.
    let unchanged = req.items.iter().all(|l| l.item_id.is_some())
        && lines.len() == old_items.len()
        && req.items.iter().zip(&lines).all(|(l, (_, n))| {
            l.item_id
                .and_then(|i| old_items.get(&i))
                .is_some_and(|o| o.quantity == n.quantity)
        });
    if unchanged {
        return Err(AppError::new(ErrorCode::NoChanges));
    }

    let total = lines.iter().try_fold(0i64, |sum, (_, l)| {
        sum.checked_add(line_total(l.quantity, l.unit_price)?)
    });
    let total = total.ok_or_else(AppError::internal)?;
    let raw_text = lines
        .iter()
        .map(|(_, l)| format!("{} {}", l.name, l.quantity.to_i64().unwrap_or_default()))
        .collect::<Vec<_>>()
        .join("\n");

    // Void first so the new items see the restored stock.
    void(tx, user_id, id, None).await?;
    let new_id = insert_transaction(
        tx,
        user_id,
        req.client_uuid,
        &raw_text,
        total,
        Some(occurred_at),
        Some(id),
    )
    .await?
    .ok_or_else(|| AppError::new(ErrorCode::AlreadyVoided))?;
    for (line_no, l) in &lines {
        // Safety net: the stock was checked above.
        insert_snapshot_item(
            tx,
            new_id,
            *line_no as i16,
            l.product_id,
            &l.name,
            l.unit_price,
            l.quantity,
        )
        .await
        .map_err(|e| match e.code() {
            ErrorCode::StockInsufficient => lines_invalid(&[LineError::new(
                *line_no,
                ErrorCode::StockInsufficient,
                "Stok tidak cukup.",
            )]),
            _ => e,
        })?;
    }
    find_by_client_uuid(tx, user_id, req.client_uuid)
        .await?
        .ok_or_else(AppError::internal)
}
