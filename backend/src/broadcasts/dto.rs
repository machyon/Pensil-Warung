//! Broadcast JSON shapes.

use serde::Serialize;
use tokio_postgres::Row;

use crate::products::dto::rfc3339;

#[derive(Serialize)]
pub struct BroadcastItem {
    pub id: i32,
    pub category: String,
    pub title: String,
    pub summary: String,
    pub has_body: bool,
    pub shown_at: String,
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
            shown_at: rfc3339(r.get("shown_at")),
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
