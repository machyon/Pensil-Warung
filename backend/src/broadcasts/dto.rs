//! Broadcast JSON shapes.

use serde::Serialize;
use time::OffsetDateTime;
use tokio_postgres::Row;

use crate::common::pagination::Page;

#[derive(Serialize)]
pub struct BroadcastItem {
    pub id: i32,
    pub category: String,
    pub title: String,
    pub summary: String,
    pub has_body: bool,
    #[serde(with = "time::serde::rfc3339")]
    pub shown_at: OffsetDateTime,
}

impl From<&Row> for BroadcastItem {
    /// Columns: `id, category` (text)`, title, summary, has_body, shown_at`.
    fn from(r: &Row) -> Self {
        BroadcastItem {
            id: r.get("id"),
            category: r.get("category"),
            title: r.get("title"),
            summary: r.get("summary"),
            has_body: r.get("has_body"),
            shown_at: r.get("shown_at"),
        }
    }
}

#[derive(Serialize)]
pub struct BroadcastWithBody {
    #[serde(flatten)]
    pub item: BroadcastItem,
    pub body: Option<String>,
}

impl From<&Row> for BroadcastWithBody {
    /// The item columns plus `body`.
    fn from(r: &Row) -> Self {
        BroadcastWithBody {
            item: r.into(),
            body: r.get("body"),
        }
    }
}

#[derive(Serialize)]
pub struct BroadcasterList {
    pub recipient_count: i64,
    pub scheduled: Vec<BroadcastItem>,
    pub sent: Page<BroadcastItem>,
}

#[derive(Serialize)]
pub struct BroadcasterDetail {
    #[serde(flatten)]
    pub broadcast: BroadcastWithBody,
    pub effective_status: String,
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    pub created_by_name: Option<String>,
    #[serde(with = "time::serde::rfc3339::option")]
    pub cancelled_at: Option<OffsetDateTime>,
    pub cancelled_by_name: Option<String>,
}

impl From<&Row> for BroadcasterDetail {
    /// The item columns plus `body, effective_status, created_at, created_by_name,
    /// cancelled_at, cancelled_by_name`.
    fn from(r: &Row) -> Self {
        BroadcasterDetail {
            broadcast: r.into(),
            effective_status: r.get("effective_status"),
            created_at: r.get("created_at"),
            created_by_name: r.get("created_by_name"),
            cancelled_at: r.get("cancelled_at"),
            cancelled_by_name: r.get("cancelled_by_name"),
        }
    }
}
