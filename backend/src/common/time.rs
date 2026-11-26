//! Calendar days are Asia/Jakarta (WIB, UTC+07:00, no DST), so a fixed offset
//! is enough and no tz database is needed.

use time::macros::offset;
use time::{Date, Duration, OffsetDateTime, UtcOffset};

pub const WIB: UtcOffset = offset!(+7);

/// `[00:00 WIB of date, 00:00 WIB of the next day)`.
pub fn wib_day_bounds(date: Date) -> (OffsetDateTime, OffsetDateTime) {
    let start = date.midnight().assume_offset(WIB);
    (start, start + Duration::days(1))
}

pub fn today_wib() -> Date {
    OffsetDateTime::now_utc().to_offset(WIB).date()
}

#[cfg(test)]
mod tests {
    use super::*;
    use time::macros::{date, datetime};

    #[test]
    fn day_starts_at_17_utc_the_day_before() {
        let (start, end) = wib_day_bounds(date!(2026 - 11 - 17));
        assert_eq!(start, datetime!(2026-11-16 17:00 UTC));
        assert_eq!(end, datetime!(2026-11-17 17:00 UTC));
    }

    #[test]
    fn today_is_a_wib_date() {
        let (start, end) = wib_day_bounds(today_wib());
        let now = OffsetDateTime::now_utc();
        assert!(start <= now && now < end);
    }
}
