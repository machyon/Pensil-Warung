//! Input validation helpers. Messages are Indonesian; `details.field` names
//! the offending field.

use rust_decimal::Decimal;

use crate::error::{AppError, ErrorCode};

/// Request DTOs implement this and handlers call it right after extraction.
pub trait Validate {
    fn validate(&self) -> Result<(), AppError>;
}

fn invalid(field: &str, message: String) -> AppError {
    AppError::validation(ErrorCode::InvalidValue, field, message)
}

/// Trims the value and rejects it if nothing is left.
pub fn trim_required(field: &str, value: &str) -> Result<String, AppError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(invalid(field, format!("{field} wajib diisi.")));
    }
    Ok(trimmed.to_owned())
}

/// Rejects values longer than `max` characters (not bytes).
pub fn max_len(field: &str, value: &str, max: usize) -> Result<(), AppError> {
    if value.chars().count() > max {
        return Err(invalid(field, format!("{field} maksimal {max} karakter.")));
    }
    Ok(())
}

/// A quantity must be a whole number greater than zero.
pub fn whole_quantity(field: &str, value: Decimal) -> Result<(), AppError> {
    if value <= Decimal::ZERO {
        return Err(invalid(field, format!("{field} harus lebih dari 0.")));
    }
    if !value.fract().is_zero() {
        return Err(invalid(
            field,
            format!("{field} harus berupa bilangan bulat."),
        ));
    }
    Ok(())
}

/// Money in whole rupiah must not be negative.
pub fn non_negative_money(field: &str, value: i64) -> Result<(), AppError> {
    if value < 0 {
        return Err(invalid(field, format!("{field} tidak boleh negatif.")));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    fn dec(s: &str) -> Decimal {
        Decimal::from_str(s).expect("decimal")
    }

    #[test]
    fn trim_required_trims_and_rejects_blank() {
        assert_eq!(trim_required("nama", "  nasi  ").unwrap(), "nasi");
        let err = trim_required("nama", "   ").unwrap_err();
        assert_eq!(err.code(), ErrorCode::InvalidValue);
        assert!(trim_required("nama", "").is_err());
    }

    #[test]
    fn max_len_counts_chars_not_bytes() {
        assert!(max_len("nama", "ééééé", 5).is_ok());
        assert!(max_len("nama", "éééééé", 5).is_err());
        assert!(max_len("nama", "", 0).is_ok());
    }

    #[test]
    fn whole_quantity_rejects_fractions_and_non_positive() {
        assert!(whole_quantity("jumlah", dec("2")).is_ok());
        assert!(whole_quantity("jumlah", dec("2.0")).is_ok());
        assert!(whole_quantity("jumlah", dec("2.5")).is_err());
        assert!(whole_quantity("jumlah", dec("0")).is_err());
        assert!(whole_quantity("jumlah", dec("-1")).is_err());
    }

    #[test]
    fn non_negative_money_allows_zero() {
        assert!(non_negative_money("harga", 0).is_ok());
        assert!(non_negative_money("harga", 15_000).is_ok());
        assert!(non_negative_money("harga", -1).is_err());
    }
}
