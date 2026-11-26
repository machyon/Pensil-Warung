//! Broadcasts: the user feed and the broadcaster screens. There is no scheduler:
//! `v_broadcasts` works out at read time whether a scheduled broadcast is due.
//! Feed reads are global (no user scoping); that is the documented exception.

pub mod dto;
pub mod handlers;

use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use tokio_postgres::GenericClient;
use uuid::Uuid;

use crate::common::pagination::{Cursor, Page};
use crate::common::validate::{max_len, trim_required};
use crate::error::{AppError, AppResult, ErrorCode};
use dto::{BroadcastItem, BroadcastWithBody, BroadcasterDetail, BroadcasterList};

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

const CATEGORIES: [&str; 4] = ["update", "berita", "info", "tips"];

fn invalid(field: &str, message: &'static str) -> AppError {
    AppError::validation(ErrorCode::InvalidValue, field, message)
}

fn check_category(category: &str) -> AppResult<()> {
    if CATEGORIES.contains(&category) {
        return Ok(());
    }
    Err(invalid(
        "category",
        "category harus update, berita, info atau tips.",
    ))
}

fn check_title(title: &str) -> AppResult<String> {
    let title = trim_required("title", title)?;
    max_len("title", &title, 60)?;
    Ok(title)
}

fn check_summary(summary: &str) -> AppResult<String> {
    let summary = trim_required("summary", summary)?;
    max_len("summary", &summary, 120)?;
    Ok(summary)
}

/// Blank becomes `None`.
fn check_body(body: &str) -> Option<String> {
    Some(body.trim().to_owned()).filter(|b| !b.is_empty())
}

/// An RFC 3339 time that is still in the future, else 422 (`time_passed` if it is past).
fn check_send_at(send_at: &str) -> AppResult<OffsetDateTime> {
    let at = OffsetDateTime::parse(send_at, &Rfc3339)
        .map_err(|_| invalid("send_at", "send_at harus berformat RFC 3339."))?;
    if at <= OffsetDateTime::now_utc() {
        return Err(AppError::validation(
            ErrorCode::TimePassed,
            "send_at",
            "Waktu kirim harus di masa depan.",
        ));
    }
    Ok(at)
}

/// A validated new broadcast. `send_at` of `None` sends it now.
pub struct NewBroadcast {
    category: String,
    title: String,
    summary: String,
    body: Option<String>,
    send_at: Option<OffsetDateTime>,
}

impl NewBroadcast {
    pub fn new(
        category: &str,
        title: &str,
        summary: &str,
        body: Option<&str>,
        send_at: Option<&str>,
    ) -> AppResult<Self> {
        check_category(category)?;
        Ok(NewBroadcast {
            category: category.to_owned(),
            title: check_title(title)?,
            summary: check_summary(summary)?,
            body: body.and_then(check_body),
            send_at: send_at.map(check_send_at).transpose()?,
        })
    }
}

/// Inserts a broadcast, sent now or scheduled, and returns its id.
pub async fn create(
    client: &impl GenericClient,
    user_id: Uuid,
    new: &NewBroadcast,
) -> AppResult<i32> {
    let row = client
        .query_one(
            "INSERT INTO broadcasts
               (category, title, summary, body, status, scheduled_for, broadcasted_at, created_by)
             VALUES ($1::text::broadcast_category, $2, $3, $4,
                     CASE WHEN $5::timestamptz IS NULL THEN 'sent' ELSE 'scheduled' END::broadcast_status,
                     $5::timestamptz,
                     CASE WHEN $5::timestamptz IS NULL THEN now() END,
                     $6)
             RETURNING id",
            &[
                &new.category,
                &new.title,
                &new.summary,
                &new.body,
                &new.send_at,
                &user_id,
            ],
        )
        .await?;
    Ok(row.get(0))
}

/// Any broadcast, whatever its status, for the broadcaster screens.
pub async fn detail(client: &impl GenericClient, id: i32) -> AppResult<Option<BroadcasterDetail>> {
    let row = client
        .query_opt(
            &format!(
                "SELECT {ITEM_COLUMNS}, body, effective_status, created_at, cancelled_at,
                        (SELECT display_name FROM users WHERE id = created_by) AS created_by_name,
                        (SELECT display_name FROM users WHERE id = cancelled_by) AS cancelled_by_name
                   FROM v_broadcasts WHERE id = $1"
            ),
            &[&id],
        )
        .await?;
    Ok(row.as_ref().map(BroadcasterDetail::from))
}
