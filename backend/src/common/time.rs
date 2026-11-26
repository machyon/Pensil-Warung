//! Calendar days are Asia/Jakarta (WIB, UTC+07:00, no DST), so a fixed offset
//! is enough and no tz database is needed.

use time::macros::{format_description, offset};
use time::{Date, Duration, OffsetDateTime, UtcOffset};

use crate::error::{AppError, AppResult, ErrorCode};

pub const WIB: UtcOffset = offset!(+7);

/// `[00:00 WIB of date, 00:00 WIB of the next day)`.
pub fn wib_day_bounds(date: Date) -> (OffsetDateTime, OffsetDateTime) {
    let start = date.midnight().assume_offset(WIB);
    (start, start + Duration::days(1))
}

pub fn today_wib() -> Date {
    OffsetDateTime::now_utc().to_offset(WIB).date()
}

/// A month is its first day, so months compare and sort as dates.
pub type Month = Date;

fn bad_month(message: &'static str) -> AppError {
    AppError::validation(ErrorCode::InvalidValue, "month", message)
}

/// "2026-11" -> 2026-11-01. `None` for any other format.
pub fn parse_month(s: &str) -> Option<Month> {
    // Exactly YYYY-MM; the length check keeps "+2026-1"-style input out.
    if s.len() != 7 {
        return None;
    }
    Date::parse(
        &format!("{s}-01"),
        format_description!("[year]-[month]-[day]"),
    )
    .ok()
}

/// "YYYY-MM".
pub fn format_month(month: Month) -> String {
    format!("{:04}-{:02}", month.year(), month.month() as u8)
}

pub fn current_month_wib() -> Month {
    today_wib().replace_day(1).expect("day 1 exists")
}

/// The `month` query parameter: default the current WIB month; a bad format or
/// a month after the current one is 422 `invalid_value` on `month`.
pub fn resolve_month(param: Option<&str>) -> AppResult<Month> {
    let current = current_month_wib();
    let month = match param {
        None => current,
        Some(s) => parse_month(s).ok_or_else(|| bad_month("Bulan harus berformat YYYY-MM."))?,
    };
    if month > current {
        return Err(bad_month("Bulan tidak boleh di masa depan."));
    }
    Ok(month)
}

/// The `{date}` path value: `YYYY-MM-DD`, not after today (WIB); otherwise
/// 422 `invalid_value` on `date`.
pub fn resolve_day(s: &str) -> AppResult<Date> {
    let bad = |m: &'static str| AppError::validation(ErrorCode::InvalidValue, "date", m);
    let day = Date::parse(s, format_description!("[year]-[month]-[day]"))
        .map_err(|_| bad("Tanggal harus berformat YYYY-MM-DD."))?;
    if day > today_wib() {
        return Err(bad("Tanggal tidak boleh di masa depan."));
    }
    Ok(day)
}

/// `[1st 00:00 WIB, next 1st 00:00 WIB)`.
pub fn month_bounds(month: Month) -> (OffsetDateTime, OffsetDateTime) {
    (wib_day_bounds(month).0, wib_day_bounds(next_month(month)).0)
}

pub fn next_month(month: Month) -> Month {
    let (year, m) = (month.year(), month.month());
    let first = if m == time::Month::December {
        Date::from_calendar_date(year + 1, time::Month::January, 1)
    } else {
        Date::from_calendar_date(year, m.next(), 1)
    };
    first.expect("valid month")
}

pub fn previous_month(month: Month) -> Month {
    let (year, m) = (month.year(), month.month());
    let first = if m == time::Month::January {
        Date::from_calendar_date(year - 1, time::Month::December, 1)
    } else {
        Date::from_calendar_date(year, m.previous(), 1)
    };
    first.expect("valid month")
}

pub fn days_in_month(month: Month) -> u8 {
    month.month().length(month.year())
}

/// Today's day for the current month, the last day for any other month.
pub fn through_day(month: Month, today: Date) -> u8 {
    if month.year() == today.year() && month.month() == today.month() {
        today.day()
    } else {
        days_in_month(month)
    }
}

/// The previous month and the days 1..=n of it that match days 1..=`through_day`
/// of `month`, clamped to its length (31 Mar -> 29 days of a leap Feb).
pub fn same_days_previous_month(month: Month, through_day: u8) -> (Month, u8) {
    let prev = previous_month(month);
    (prev, through_day.min(days_in_month(prev)))
}

/// `[1st 00:00 WIB, 1st + days 00:00 WIB)`: the first `days` days of a month.
pub fn month_days_bounds(month: Month, days: u8) -> (OffsetDateTime, OffsetDateTime) {
    let start = wib_day_bounds(month).0;
    (start, start + Duration::days(days.into()))
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

    #[test]
    fn parses_only_yyyy_mm() {
        assert_eq!(parse_month("2026-11"), Some(date!(2026 - 11 - 01)));
        for bad in [
            "2026-13",
            "2026-1",
            "2026-00",
            "26-11",
            "2026-11-01",
            "",
            "abcd-ef",
        ] {
            assert_eq!(parse_month(bad), None, "{bad}");
        }
        assert_eq!(format_month(date!(2026 - 01 - 01)), "2026-01");
    }

    #[test]
    fn bounds_start_at_17_utc_the_day_before() {
        let (start, end) = month_bounds(date!(2026 - 11 - 01));
        assert_eq!(start, datetime!(2026-10-31 17:00 UTC));
        assert_eq!(end, datetime!(2026-11-30 17:00 UTC));
    }

    #[test]
    fn december_rolls_into_january() {
        let dec = date!(2026 - 12 - 01);
        assert_eq!(next_month(dec), date!(2027 - 01 - 01));
        assert_eq!(previous_month(date!(2027 - 01 - 01)), dec);
        assert_eq!(month_bounds(dec).1, datetime!(2026-12-31 17:00 UTC));
    }

    #[test]
    fn leap_years_and_clamping() {
        assert_eq!(days_in_month(date!(2024 - 02 - 01)), 29);
        assert_eq!(days_in_month(date!(2026 - 02 - 01)), 28);
        // 31 Mar compares with all of Feb, whatever its length.
        assert_eq!(
            same_days_previous_month(date!(2024 - 03 - 01), 31),
            (date!(2024 - 02 - 01), 29)
        );
        assert_eq!(
            same_days_previous_month(date!(2026 - 03 - 01), 31),
            (date!(2026 - 02 - 01), 28)
        );
        assert_eq!(
            same_days_previous_month(date!(2026 - 11 - 01), 17),
            (date!(2026 - 10 - 01), 17)
        );
        assert_eq!(
            same_days_previous_month(date!(2027 - 01 - 01), 5),
            (date!(2026 - 12 - 01), 5)
        );
    }

    #[test]
    fn through_day_is_today_only_for_the_current_month() {
        let today = date!(2026 - 11 - 17);
        assert_eq!(through_day(date!(2026 - 11 - 01), today), 17);
        assert_eq!(through_day(date!(2026 - 10 - 01), today), 31);
        assert_eq!(through_day(date!(2025 - 11 - 01), today), 30);
    }

    #[test]
    fn days_bounds_cover_the_first_n_days() {
        let (start, end) = month_days_bounds(date!(2026 - 10 - 01), 17);
        assert_eq!(start, datetime!(2026-09-30 17:00 UTC));
        assert_eq!(end, datetime!(2026-10-17 17:00 UTC));
    }

    #[test]
    fn resolve_month_rejects_bad_and_future() {
        assert_eq!(resolve_month(None).unwrap(), current_month_wib());
        let next = format_month(next_month(current_month_wib()));
        for bad in ["nope", next.as_str()] {
            let e = resolve_month(Some(bad)).unwrap_err();
            assert_eq!(e.code(), ErrorCode::InvalidValue, "{bad}");
        }
        assert!(resolve_month(Some("2020-01")).is_ok());
    }
}
