//! Keyset paging on `(occurred_at DESC, id DESC)` with an opaque cursor.

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde::Serialize;
use time::macros::format_description;
use time::{Date, OffsetDateTime};

use crate::error::{AppError, ErrorCode};

pub const DEFAULT_LIMIT: i64 = 20;
pub const MAX_LIMIT: i64 = 100;

/// `limit` query value clamped to `1..=100`, default 20.
pub fn clamp_limit(limit: Option<i64>) -> i64 {
    limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
}

/// Position of the last row of a page. Microseconds, the precision of `timestamptz`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cursor {
    pub occurred_at: OffsetDateTime,
    pub id: i64,
}

impl Cursor {
    pub fn encode(&self) -> String {
        let micros = self.occurred_at.unix_timestamp_nanos() / 1000;
        URL_SAFE_NO_PAD.encode(format!("{micros}:{}", self.id))
    }

    /// A malformed cursor is 422 `invalid_value` on field `cursor`.
    pub fn decode(s: &str) -> Result<Self, AppError> {
        let bad = || AppError::validation(ErrorCode::InvalidValue, "cursor", "Cursor tidak valid.");
        let raw = URL_SAFE_NO_PAD.decode(s).map_err(|_| bad())?;
        let raw = String::from_utf8(raw).map_err(|_| bad())?;
        let (micros, id) = raw.split_once(':').ok_or_else(bad)?;
        let micros: i128 = micros.parse().map_err(|_| bad())?;
        let occurred_at =
            OffsetDateTime::from_unix_timestamp_nanos(micros * 1000).map_err(|_| bad())?;
        Ok(Cursor {
            occurred_at,
            id: id.parse().map_err(|_| bad())?,
        })
    }
}

/// Cursor of a day-keyed list: the last day returned, as "YYYY-MM-DD".
pub fn encode_day(day: impl std::fmt::Display) -> String {
    URL_SAFE_NO_PAD.encode(day.to_string())
}

/// A malformed cursor is 422 `invalid_value` on field `cursor`.
pub fn decode_day(s: &str) -> Result<Date, AppError> {
    let bad = || AppError::validation(ErrorCode::InvalidValue, "cursor", "Cursor tidak valid.");
    let raw = URL_SAFE_NO_PAD.decode(s).map_err(|_| bad())?;
    let raw = String::from_utf8(raw).map_err(|_| bad())?;
    Date::parse(&raw, format_description!("[year]-[month]-[day]")).map_err(|_| bad())
}

#[derive(Serialize)]
pub struct Page<T> {
    pub items: Vec<T>,
    pub next_cursor: Option<String>,
}

impl<T> Page<T> {
    /// `rows` were fetched with `LIMIT limit + 1`: an extra row means there is
    /// a next page, and the cursor points at the last row that is kept.
    pub fn new(rows: Vec<T>, limit: i64, key: impl Fn(&T) -> Cursor) -> Self {
        Self::with_key(rows, limit, |r| key(r).encode())
    }

    /// Like `new` for a cursor that is not a `Cursor`, given as its encoded form.
    pub fn with_key(mut rows: Vec<T>, limit: i64, key: impl Fn(&T) -> String) -> Self {
        let limit = limit as usize;
        let next_cursor = (rows.len() > limit).then(|| {
            rows.truncate(limit);
            key(&rows[limit - 1])
        });
        Page {
            items: rows,
            next_cursor,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use time::macros::datetime;

    #[test]
    fn cursor_round_trips() {
        let c = Cursor {
            occurred_at: datetime!(2026-11-17 03:04:05.123456 UTC),
            id: 42,
        };
        assert_eq!(Cursor::decode(&c.encode()).unwrap(), c);
    }

    #[test]
    fn tampered_cursors_are_rejected() {
        for bad in [
            "",
            "!!!",
            "bm90LWEtY3Vyc29y", // "not-a-cursor"
            &URL_SAFE_NO_PAD.encode("abc:1"),
            &URL_SAFE_NO_PAD.encode("1:abc"),
            &URL_SAFE_NO_PAD.encode("99999999999999999999999999:1"),
        ] {
            let err = Cursor::decode(bad).unwrap_err();
            assert_eq!(err.code(), ErrorCode::InvalidValue, "{bad}");
        }
    }

    #[test]
    fn day_cursor_round_trips_and_rejects_junk() {
        let d = time::macros::date!(2026 - 11 - 17);
        assert_eq!(decode_day(&encode_day(d)).unwrap(), d);
        assert!(decode_day("!!!").is_err());
        assert!(decode_day(&URL_SAFE_NO_PAD.encode("2026-13-01")).is_err());
    }

    #[test]
    fn limit_is_clamped() {
        assert_eq!(clamp_limit(None), 20);
        assert_eq!(clamp_limit(Some(0)), 1);
        assert_eq!(clamp_limit(Some(-5)), 1);
        assert_eq!(clamp_limit(Some(500)), 100);
        assert_eq!(clamp_limit(Some(7)), 7);
    }

    #[test]
    fn page_cursor_only_when_more_rows() {
        let key = |n: &i64| Cursor {
            occurred_at: datetime!(2026-01-01 0:00 UTC),
            id: *n,
        };
        let p = Page::new(vec![3, 2, 1], 2, key);
        assert_eq!(p.items, [3, 2]);
        assert_eq!(Cursor::decode(&p.next_cursor.unwrap()).unwrap().id, 2);
        assert!(Page::new(vec![3, 2], 2, key).next_cursor.is_none());
    }
}
