//! Broadcasts: the user feed and the broadcaster screens. There is no scheduler:
//! `v_broadcasts` works out at read time whether a scheduled broadcast is due.
//! Feed reads are global (no user scoping); that is the documented exception.

pub mod dto;
pub mod handlers;

use tokio_postgres::GenericClient;

use crate::common::pagination::{Cursor, Page};
use crate::error::AppResult;
use dto::{BroadcastItem, BroadcastWithBody, BroadcasterList};

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

/// Broadcaster home: every scheduled (not yet due) broadcast, soonest first,
/// and a page of the sent ones. Cancelled ones are left out.
pub async fn broadcaster_list(
    client: &impl GenericClient,
    before: Option<Cursor>,
    limit: i64,
) -> AppResult<BroadcasterList> {
    let recipient_count = client
        .query_one("SELECT count(*) FROM users WHERE role_id = 1", &[])
        .await?
        .get(0);
    let scheduled = client
        .query(
            &format!(
                "SELECT {ITEM_COLUMNS} FROM v_broadcasts
                  WHERE effective_status = 'scheduled' ORDER BY shown_at, id"
            ),
            &[],
        )
        .await?;
    let (at, id) = (before.map(|c| c.occurred_at), before.map(|c| c.id));
    let sent = client
        .query(
            &format!(
                "SELECT {ITEM_COLUMNS} FROM v_broadcasts
                  WHERE effective_status = 'sent'
                    AND ($1::timestamptz IS NULL OR (shown_at, id) < ($1, $2::bigint))
                  ORDER BY shown_at DESC, id DESC LIMIT $3"
            ),
            &[&at, &id, &(limit + 1)],
        )
        .await?;
    let sent = sent.iter().map(BroadcastItem::from).collect();
    Ok(BroadcasterList {
        recipient_count,
        scheduled: scheduled.iter().map(BroadcastItem::from).collect(),
        sent: Page::new(sent, limit, |b| Cursor {
            occurred_at: b.shown_at,
            id: b.id.into(),
        }),
    })
}
