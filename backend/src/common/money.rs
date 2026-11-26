//! Money math. Money is whole rupiah as `i64`; quantities stay `Decimal`.

use rust_decimal::prelude::ToPrimitive;
use rust_decimal::{Decimal, RoundingStrategy};

/// `round(quantity * unit_price)`, the same value as the DB check
/// `items_line_total_ok` (PostgreSQL rounds halves away from zero). `None` on overflow.
pub fn line_total(quantity: Decimal, unit_price: i64) -> Option<i64> {
    quantity
        .checked_mul(Decimal::from(unit_price))?
        .round_dp_with_strategy(0, RoundingStrategy::MidpointAwayFromZero)
        .to_i64()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    fn dec(s: &str) -> Decimal {
        Decimal::from_str(s).expect("decimal")
    }

    #[test]
    fn whole_quantity_times_price() {
        assert_eq!(line_total(dec("2"), 15_000), Some(30_000));
        assert_eq!(line_total(dec("3"), 0), Some(0));
    }

    #[test]
    fn rounds_half_away_from_zero_like_postgres() {
        assert_eq!(line_total(dec("0.5"), 5), Some(3));
        assert_eq!(line_total(dec("1.5"), 3), Some(5));
        assert_eq!(line_total(dec("0.333"), 1_000), Some(333));
    }

    #[test]
    fn overflow_is_none() {
        assert_eq!(line_total(dec("999999999"), i64::MAX), None);
        assert_eq!(line_total(dec("2"), i64::MAX), None);
    }
}
