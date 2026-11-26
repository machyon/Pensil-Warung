//! Broadcasts: the user feed and the broadcaster screens. There is no scheduler:
//! `v_broadcasts` works out at read time whether a scheduled broadcast is due.
//! Feed reads are global (no user scoping); that is the documented exception.

pub mod dto;
pub mod handlers;

use tokio_postgres::GenericClient;

use crate::error::AppResult;
use dto::{BroadcastItem, BroadcastWithBody};

/// Columns `BroadcastItem` reads.
const ITEM_COLUMNS: &str =
    "id, category::text AS category, title, summary, body IS NOT NULL AS has_body, shown_at";

/// The latest 5 broadcasts that count as sent.
pub async fn feed(client: &impl GenericClient) -> AppResult<Vec<BroadcastItem>> {
    let rows = client
        .query(
            &format!(
                "SELECT {ITEM_COLUMNS} FROM v_broadcasts
                  WHERE effective_status = 'sent' ORDER BY shown_at DESC, id DESC LIMIT 5"
            ),
            &[],
        )
        .await?;
    Ok(rows.iter().map(BroadcastItem::from).collect())
}

/// One broadcast with its body; `None` unless it counts as sent.
pub async fn feed_one(
    client: &impl GenericClient,
    id: i32,
) -> AppResult<Option<BroadcastWithBody>> {
    let row = client
        .query_opt(
            &format!(
                "SELECT {ITEM_COLUMNS}, body FROM v_broadcasts
                  WHERE id = $1 AND effective_status = 'sent'"
            ),
            &[&id],
        )
        .await?;
    Ok(row.as_ref().map(BroadcastWithBody::from))
}
