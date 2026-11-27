//! Executes a [`Plan`] inside the batch transaction. Stock only changes
//! through inserted movements: the item trigger writes the sale movements.

use std::collections::{BTreeSet, HashMap};

use rust_decimal::Decimal;
use rust_decimal::prelude::ToPrimitive;
use tokio_postgres::GenericClient;
use uuid::Uuid;

use super::dto::{Batch, CatatResponse, LineError, ProductStock, lines_invalid};
use super::plan::{Plan, ProductRef, Step};
use crate::common::money::line_total;
use crate::error::{AppError, AppResult, ErrorCode};
use crate::products::{self, NewProduct};
use crate::transactions::dto::TransactionResponse;
use crate::transactions::{TRANSACTION_COLUMNS, with_items};

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
            &format!("SELECT {TRANSACTION_COLUMNS} FROM transactions WHERE user_id = $1 AND client_uuid = $2"),
            &[&user_id, &client_uuid],
        )
        .await?
    else {
        return Ok(None);
    };
    Ok(Some(with_items(client, &row).await?))
}

/// The user's products among `ids` with their current stock, ordered by id.
/// Deleted products are simply absent.
pub async fn product_stocks(
    client: &impl GenericClient,
    user_id: Uuid,
    ids: &[i64],
) -> AppResult<Vec<ProductStock>> {
    let rows = client
        .query(
            "SELECT id, name, stock FROM products
             WHERE user_id = $1 AND id = ANY($2) ORDER BY id",
            &[&user_id, &ids],
        )
        .await?;
    Ok(rows
        .iter()
        .map(|r| ProductStock {
            id: r.get("id"),
            name: r.get("name"),
            stock: r.get::<_, Decimal>("stock").to_i64().unwrap_or_default(),
        })
        .collect())
}

/// Runs the plan's steps in order inside the caller's transaction. Returns the
/// response plus the photo keys of deleted products (delete those objects after
/// commit), or `None` when a concurrent request with the same `client_uuid`
/// already stored the transaction.
pub async fn execute(
    tx: &impl GenericClient,
    user_id: Uuid,
    batch: &Batch,
    plan: Plan,
) -> AppResult<Option<(CatatResponse, Vec<String>)>> {
    let has_sale = plan.steps.iter().any(|s| matches!(s, Step::Sale { .. }));
    let transaction_id = if has_sale {
        match insert_transaction(tx, user_id, batch.client_uuid, &batch.raw_text, plan.total)
            .await?
        {
            Some(id) => Some(id),
            None => return Ok(None),
        }
    } else {
        None
    };

    // line_no of a CreateProduct step -> the id it got.
    let mut created: HashMap<u32, i64> = HashMap::new();
    let mut touched: BTreeSet<i64> = BTreeSet::new();
    let mut deleted: Vec<i64> = Vec::new();
    let mut photo_keys: Vec<String> = Vec::new();
    let resolve = |created: &HashMap<u32, i64>, r: ProductRef| match r {
        ProductRef::Existing(id) => Ok(id),
        ProductRef::Created(line) => created.get(&line).copied().ok_or_else(AppError::internal),
    };

    for step in plan.steps {
        let line_no = match &step {
            Step::Sale { line_no, .. }
            | Step::Restock { line_no, .. }
            | Step::AdjustDown { line_no, .. }
            | Step::SetPrice { line_no, .. }
            | Step::CreateProduct { line_no, .. }
            | Step::DeleteProduct { line_no, .. } => *line_no,
        };
        let result: AppResult<()> = async {
            match step {
                Step::Sale {
                    product,
                    quantity,
                    unit_price,
                    ..
                } => {
                    let id = resolve(&created, product)?;
                    // has_sale is true, so the transaction exists.
                    let tid = transaction_id.ok_or_else(AppError::internal)?;
                    insert_item(tx, user_id, tid, line_no, id, quantity, unit_price).await?;
                    touched.insert(id);
                }
                Step::Restock {
                    product, quantity, ..
                } => {
                    let id = resolve(&created, product)?;
                    products::move_stock(tx, id, quantity, "restock", None).await?;
                    touched.insert(id);
                }
                Step::AdjustDown {
                    product, quantity, ..
                } => {
                    let id = resolve(&created, product)?;
                    products::move_stock(tx, id, -quantity, "adjustment", None).await?;
                    touched.insert(id);
                }
                Step::SetPrice { product, price, .. } => {
                    let id = resolve(&created, product)?;
                    products::set_price(tx, user_id, id, price).await?;
                    touched.insert(id);
                }
                Step::CreateProduct {
                    name, price, stock, ..
                } => {
                    let p = products::create(tx, user_id, &NewProduct::new(&name, price, stock)?)
                        .await?;
                    created.insert(line_no, p.id);
                    touched.insert(p.id);
                }
                Step::DeleteProduct { product, .. } => {
                    let id = resolve(&created, product)?;
                    let key = products::delete(tx, user_id, id)
                        .await?
                        .ok_or_else(AppError::internal)?;
                    touched.remove(&id);
                    // A product made in this batch was never visible to the client.
                    if matches!(product, ProductRef::Existing(_)) {
                        deleted.push(id);
                    }
                    photo_keys.extend(key);
                }
            }
            Ok(())
        }
        .await;
        // Safety net: the planner already checked stock.
        result.map_err(|e| match e.code() {
            ErrorCode::StockInsufficient => lines_invalid(&[LineError::new(
                line_no,
                ErrorCode::StockInsufficient,
                "Stok tidak cukup.",
            )]),
            _ => e,
        })?;
    }

    let transaction = match transaction_id {
        Some(_) => find_by_client_uuid(tx, user_id, batch.client_uuid).await?,
        None => None,
    };
    let ids: Vec<i64> = touched.into_iter().collect();
    let products_changed = product_stocks(tx, user_id, &ids).await?;
    Ok(Some((
        CatatResponse {
            transaction,
            products_changed,
            products_deleted: deleted,
        },
        photo_keys,
    )))
}
