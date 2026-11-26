//! Executes a [`Plan`] inside the batch transaction. Stock only changes
//! through inserted movements: the item trigger writes the sale movements.

use rust_decimal::Decimal;
use tokio_postgres::GenericClient;
use uuid::Uuid;

use super::dto::{LineError, lines_invalid};
use crate::common::money::line_total;
use crate::error::{AppError, AppResult, ErrorCode};
use crate::transactions::dto::{ItemResponse, TransactionResponse};

/// Inserts the transaction row. `None` means the user already has one with this
/// `client_uuid` (a concurrent duplicate won): the caller replays it.
pub async fn insert_transaction(
    client: &impl GenericClient,
    user_id: Uuid,
    client_uuid: Uuid,
    raw_text: &str,
    total: i64,
) -> AppResult<Option<i64>> {
    let row = client
        .query_opt(
            "INSERT INTO transactions (user_id, client_uuid, raw_text, total)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT ON CONSTRAINT transactions_client_uuid_key DO NOTHING
             RETURNING id",
            &[&user_id, &client_uuid, &raw_text, &total],
        )
        .await?;
    Ok(row.map(|r| r.get(0)))
}

/// Inserts one item. The name snapshot is read from the user's product, and the
/// price and total come from the plan, never from the client. The trigger
/// records the `sale` movement (and a short stock fails with 23514).
pub async fn insert_item(
    client: &impl GenericClient,
    user_id: Uuid,
    transaction_id: i64,
    line_no: u32,
    product_id: i64,
    quantity: Decimal,
    unit_price: i64,
) -> AppResult<()> {
    let line_no16 = i16::try_from(line_no).map_err(|_| {
        lines_invalid(&[LineError::new(
            line_no,
            ErrorCode::InvalidValue,
            "line_no terlalu besar.",
        )])
    })?;
    let total = line_total(quantity, unit_price).ok_or_else(AppError::internal)?;
    let n = client
        .execute(
            "INSERT INTO transaction_items
               (transaction_id, product_id, line_no, product_name, unit_price, quantity, line_total)
             SELECT $1::bigint, p.id, $3::smallint, p.name, $4::bigint, $5::numeric, $6::bigint
               FROM products p WHERE p.id = $2 AND p.user_id = $7",
            &[
                &transaction_id,
                &product_id,
                &line_no16,
                &unit_price,
                &quantity,
                &total,
                &user_id,
            ],
        )
        .await?;
    if n != 1 {
        return Err(AppError::internal());
    }
    Ok(())
}

/// The user's transaction with this `client_uuid`, with its items, if any.
pub async fn find_by_client_uuid(
    client: &impl GenericClient,
    user_id: Uuid,
    client_uuid: Uuid,
) -> AppResult<Option<TransactionResponse>> {
    let Some(row) = client
        .query_opt(
            "SELECT id, raw_text, total, status::text AS status, occurred_at, voided_at, void_reason
               FROM transactions WHERE user_id = $1 AND client_uuid = $2",
            &[&user_id, &client_uuid],
        )
        .await?
    else {
        return Ok(None);
    };
    let items = client
        .query(
            "SELECT id, line_no, product_id, product_name, unit_price, quantity, line_total
               FROM transaction_items WHERE transaction_id = $1 ORDER BY line_no",
            &[&row.get::<_, i64>("id")],
        )
        .await?;
    let items = items.iter().map(ItemResponse::from).collect();
    Ok(Some(TransactionResponse::new(&row, items)))
}
