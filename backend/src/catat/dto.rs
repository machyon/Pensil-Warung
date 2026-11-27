//! The POST /catat request and its validation.
//!
//! Numbers arrive as JSON numbers (not Rust integers or decimals) so that
//! `2.5` is a per-line error instead of a 400 for the whole body.

use std::collections::HashSet;

use rust_decimal::Decimal;
use rust_decimal::prelude::ToPrimitive;
use serde::{Deserialize, Serialize};
use serde_json::{Number, json};
use uuid::Uuid;

use crate::common::names::{name_key, normalize_product_name};
use crate::common::validate::{MAX_QUANTITY, whole_quantity};
use crate::error::{AppError, ErrorCode};
use crate::products;
use crate::transactions::dto::TransactionResponse;

const MAX_OPS: usize = 200;
const MAX_RAW_TEXT_CHARS: usize = 20_000;
const MAX_NAME_CHARS: usize = 60;

#[derive(Debug, Deserialize)]
pub struct CatatRequest {
    pub client_uuid: Uuid,
    pub raw_text: String,
    pub ops: Vec<OpDto>,
}

/// One line as sent by the client. Unknown fields are ignored.
#[derive(Debug, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum OpDto {
    Sale {
        line_no: u32,
        product: String,
        quantity: Number,
    },
    Restock {
        line_no: u32,
        product: String,
        quantity: Number,
    },
    AdjustDown {
        line_no: u32,
        product: String,
        quantity: Number,
        note: Option<String>,
    },
    SetPrice {
        line_no: u32,
        product: String,
        price: Number,
    },
    CreateProduct {
        line_no: u32,
        name: String,
        price: Number,
        stock: Number,
    },
    DeleteProduct {
        line_no: u32,
        product: String,
    },
}

impl OpDto {
    fn line_no(&self) -> u32 {
        match self {
            OpDto::Sale { line_no, .. }
            | OpDto::Restock { line_no, .. }
            | OpDto::AdjustDown { line_no, .. }
            | OpDto::SetPrice { line_no, .. }
            | OpDto::CreateProduct { line_no, .. }
            | OpDto::DeleteProduct { line_no, .. } => *line_no,
        }
    }
}

/// A problem with one line. Serialized as `{line_no, code, message}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LineError {
    pub line_no: u32,
    pub code: ErrorCode,
    pub message: String,
}

impl LineError {
    pub fn new(line_no: u32, code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            line_no,
            code,
            message: message.into(),
        }
    }
}

/// 422 `lines_invalid` with `details.lines: [{line_no, code, message}]`.
pub fn lines_invalid(lines: &[LineError]) -> AppError {
    AppError::new(ErrorCode::LinesInvalid).with_details(json!({ "lines": lines }))
}

/// A product touched by a batch, with its stock now.
#[derive(Debug, Serialize)]
pub struct ProductStock {
    pub id: i64,
    pub name: String,
    pub stock: i64,
}

/// The `POST /catat` response body.
#[derive(Serialize)]
pub struct CatatResponse {
    pub transaction: Option<TransactionResponse>,
    pub products_changed: Vec<ProductStock>,
    pub products_deleted: Vec<i64>,
}

/// A validated line. Product references are `name_key`s (lowercase, single
/// spaces) so the planner can match them against the user's products.
#[derive(Debug, Clone, PartialEq)]
pub enum Op {
    Sale {
        line_no: u32,
        key: String,
        quantity: Decimal,
    },
    Restock {
        line_no: u32,
        key: String,
        quantity: Decimal,
    },
    /// `note` is trimmed, at most 200 characters, `None` when blank.
    AdjustDown {
        line_no: u32,
        key: String,
        quantity: Decimal,
        note: Option<String>,
    },
    SetPrice {
        line_no: u32,
        key: String,
        price: i64,
    },
    /// `name` is normalized (trimmed, single spaces), 1-60 characters.
    CreateProduct {
        line_no: u32,
        name: String,
        price: i64,
        stock: i64,
    },
    DeleteProduct {
        line_no: u32,
        key: String,
    },
}

impl Op {
    pub fn line_no(&self) -> u32 {
        match self {
            Op::Sale { line_no, .. }
            | Op::Restock { line_no, .. }
            | Op::AdjustDown { line_no, .. }
            | Op::SetPrice { line_no, .. }
            | Op::CreateProduct { line_no, .. }
            | Op::DeleteProduct { line_no, .. } => *line_no,
        }
    }
}

/// A fully validated request. `ops` are sorted by `line_no`.
#[derive(Debug)]
pub struct Batch {
    pub client_uuid: Uuid,
    pub raw_text: String,
    pub ops: Vec<Op>,
}

impl CatatRequest {
    /// Batch checks give 422 `invalid_value`; line checks are all collected into
    /// 422 `lines_invalid`. `raw_text` is kept exactly as typed.
    pub fn validate(self) -> Result<Batch, AppError> {
        let batch_err = |field: &str, msg: &str| {
            AppError::validation(ErrorCode::InvalidValue, field, msg.to_owned())
        };
        if self.ops.is_empty() || self.ops.len() > MAX_OPS {
            return Err(batch_err("ops", "ops harus berisi 1-200 baris."));
        }
        if self.raw_text.trim().is_empty() {
            return Err(batch_err("raw_text", "raw_text wajib diisi."));
        }
        if self.raw_text.chars().count() > MAX_RAW_TEXT_CHARS {
            return Err(batch_err("raw_text", "raw_text terlalu panjang."));
        }
        let mut seen = HashSet::new();
        if !self.ops.iter().all(|op| seen.insert(op.line_no())) {
            return Err(batch_err("ops", "line_no harus unik."));
        }

        let (mut ops, mut errors) = validate_ops(&self.ops);
        if !errors.is_empty() {
            errors.sort_by_key(|e| e.line_no);
            return Err(lines_invalid(&errors));
        }
        ops.sort_by_key(Op::line_no);
        Ok(Batch {
            client_uuid: self.client_uuid,
            raw_text: self.raw_text,
            ops,
        })
    }
}

fn validate_ops(dtos: &[OpDto]) -> (Vec<Op>, Vec<LineError>) {
    let mut ops = Vec::with_capacity(dtos.len());
    let mut errors = Vec::new();
    for dto in dtos {
        match validate_op(dto) {
            Ok(op) => ops.push(op),
            Err(e) => errors.push(e),
        }
    }
    (ops, errors)
}

fn validate_op(dto: &OpDto) -> Result<Op, LineError> {
    let line_no = dto.line_no();
    match dto {
        OpDto::Sale {
            product, quantity, ..
        } => Ok(Op::Sale {
            line_no,
            key: product_key(line_no, product)?,
            quantity: quantity_of(line_no, quantity)?,
        }),
        OpDto::Restock {
            product, quantity, ..
        } => Ok(Op::Restock {
            line_no,
            key: product_key(line_no, product)?,
            quantity: quantity_of(line_no, quantity)?,
        }),
        OpDto::AdjustDown {
            product,
            quantity,
            note,
            ..
        } => Ok(Op::AdjustDown {
            line_no,
            key: product_key(line_no, product)?,
            quantity: quantity_of(line_no, quantity)?,
            note: products::clean_note(note.as_deref()).map_err(|_| {
                LineError::new(
                    line_no,
                    ErrorCode::InvalidValue,
                    "Alasan maksimal 200 karakter.",
                )
            })?,
        }),
        OpDto::SetPrice { product, price, .. } => Ok(Op::SetPrice {
            line_no,
            key: product_key(line_no, product)?,
            price: price_of(line_no, price)?,
        }),
        OpDto::DeleteProduct { product, .. } => Ok(Op::DeleteProduct {
            line_no,
            key: product_key(line_no, product)?,
        }),
        OpDto::CreateProduct {
            name, price, stock, ..
        } => {
            let name = normalize_product_name(name);
            if name.is_empty() || name.chars().count() > MAX_NAME_CHARS {
                return Err(LineError::new(
                    line_no,
                    ErrorCode::InvalidName,
                    "Nama produk 1-60 karakter.",
                ));
            }
            Ok(Op::CreateProduct {
                line_no,
                name,
                price: price_of(line_no, price)?,
                stock: whole_number(stock)
                    .and_then(|d| d.to_i64())
                    .filter(|s| (0..=MAX_QUANTITY).contains(s))
                    .ok_or_else(|| {
                        LineError::new(
                            line_no,
                            ErrorCode::InvalidValue,
                            format!("Stok harus bilangan bulat 0-{MAX_QUANTITY}."),
                        )
                    })?,
            })
        }
    }
}

fn product_key(line_no: u32, product: &str) -> Result<String, LineError> {
    let key = name_key(product);
    if key.is_empty() {
        return Err(LineError::new(
            line_no,
            ErrorCode::InvalidName,
            "Nama produk wajib diisi.",
        ));
    }
    Ok(key)
}

/// A JSON number as a `Decimal`, `None` if it is not representable (such as `1e30`).
fn to_decimal(n: &Number) -> Option<Decimal> {
    n.to_string().parse().ok()
}

/// A JSON number that is a whole number (`2` and `2.0` both count).
fn whole_number(n: &Number) -> Option<Decimal> {
    to_decimal(n).filter(|d| d.fract().is_zero())
}

fn price_of(line_no: u32, n: &Number) -> Result<i64, LineError> {
    whole_number(n)
        .and_then(|d| d.to_i64())
        .filter(|p| *p >= 0)
        .ok_or_else(|| {
            LineError::new(
                line_no,
                ErrorCode::InvalidPrice,
                "Harga harus berupa bilangan bulat, tidak boleh negatif.",
            )
        })
}

fn quantity_of(line_no: u32, n: &Number) -> Result<Decimal, LineError> {
    let invalid = |msg: String| LineError::new(line_no, ErrorCode::InvalidQuantity, msg);
    let d = to_decimal(n).ok_or_else(|| invalid("Jumlah tidak valid.".into()))?;
    whole_quantity("Jumlah", d).map_err(|e| invalid(e.message().to_owned()))?;
    Ok(d)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};

    fn request(ops: Value) -> CatatRequest {
        serde_json::from_value(json!({
            "client_uuid": "0193a1b2-0000-7000-8000-000000000000",
            "raw_text": "nasi goreng 2",
            "ops": ops,
        }))
        .expect("request")
    }

    #[test]
    fn parses_every_op_and_ignores_unknown_fields() {
        let batch = request(json!([
            {"line_no": 3, "op": "delete_product", "product": " Kopi  Susu "},
            {"line_no": 1, "op": "sale", "product": "Nasi Goreng", "quantity": 2, "price": 1, "occurred_at": "x"},
            {"line_no": 2, "op": "create_product", "name": "Es  Teh", "price": 5000, "stock": 10},
            {"line_no": 4, "op": "restock", "product": "a", "quantity": 2.0},
            {"line_no": 5, "op": "adjust_down", "product": "a", "quantity": 1},
            {"line_no": 6, "op": "set_price", "product": "a", "price": 6000},
            {"line_no": 7, "op": "adjust_down", "product": "a", "quantity": 1, "note": "  basi "},
        ]))
        .validate()
        .expect("valid");
        let nos: Vec<u32> = batch.ops.iter().map(Op::line_no).collect();
        assert_eq!(nos, [1, 2, 3, 4, 5, 6, 7]);
        assert_eq!(
            batch.ops[5],
            Op::SetPrice {
                line_no: 6,
                key: "a".into(),
                price: 6000
            }
        );
        assert!(matches!(&batch.ops[6], Op::AdjustDown { note: Some(n), .. } if n == "basi"));
        assert_eq!(
            batch.ops[0],
            Op::Sale {
                line_no: 1,
                key: "nasi goreng".into(),
                quantity: Decimal::from(2)
            }
        );
        assert_eq!(
            batch.ops[1],
            Op::CreateProduct {
                line_no: 2,
                name: "Es Teh".into(),
                price: 5000,
                stock: 10
            }
        );
        assert_eq!(
            batch.ops[2],
            Op::DeleteProduct {
                line_no: 3,
                key: "kopi susu".into()
            }
        );
    }

    #[test]
    fn unknown_op_is_a_body_error() {
        let r: Result<CatatRequest, _> = serde_json::from_value(json!({
            "client_uuid": "0193a1b2-0000-7000-8000-000000000000",
            "raw_text": "x",
            "ops": [{"line_no": 1, "op": "explode"}],
        }));
        assert!(r.is_err());
    }

    #[test]
    fn batch_level_checks() {
        let ok = json!({"line_no": 1, "op": "sale", "product": "a", "quantity": 1});
        let e = request(json!([])).validate().unwrap_err();
        assert_eq!(e.code(), ErrorCode::InvalidValue);
        let many: Vec<Value> = (1..=201)
            .map(|n| json!({"line_no": n, "op": "sale", "product": "a", "quantity": 1}))
            .collect();
        assert!(request(json!(many)).validate().is_err());
        let dup = json!({"line_no": 1, "op": "restock", "product": "a", "quantity": 1});
        assert!(request(json!([ok.clone(), dup])).validate().is_err());
        let mut r = request(json!([ok.clone()]));
        r.raw_text = "  \n".into();
        assert!(r.validate().is_err());
        let mut r = request(json!([ok]));
        r.raw_text = "x".repeat(MAX_RAW_TEXT_CHARS + 1);
        assert!(r.validate().is_err());
    }

    #[test]
    fn bad_values_become_line_errors_not_400() {
        let errors = validate_ops(
            &request(json!([
                {"line_no": 1, "op": "sale", "product": "a", "quantity": 2.5},
                {"line_no": 2, "op": "restock", "product": "a", "quantity": 0},
                {"line_no": 3, "op": "adjust_down", "product": "a", "quantity": 1000000000},
                {"line_no": 4, "op": "create_product", "name": "x", "price": 1.5, "stock": 1},
                {"line_no": 5, "op": "create_product", "name": "x", "price": -1, "stock": 1},
                {"line_no": 6, "op": "create_product", "name": "   ", "price": 1, "stock": 1},
                {"line_no": 7, "op": "create_product", "name": "x", "price": 1, "stock": 1.5},
                {"line_no": 8, "op": "sale", "product": "  ", "quantity": 1},
                {"line_no": 9, "op": "sale", "product": "a", "quantity": 1e30},
                {"line_no": 10, "op": "sale", "product": "a", "quantity": 1},
            ]))
            .ops,
        )
        .1;
        let got: Vec<_> = errors.iter().map(|e| (e.line_no, e.code)).collect();
        assert_eq!(
            got,
            [
                (1, ErrorCode::InvalidQuantity),
                (2, ErrorCode::InvalidQuantity),
                (3, ErrorCode::InvalidQuantity),
                (4, ErrorCode::InvalidPrice),
                (5, ErrorCode::InvalidPrice),
                (6, ErrorCode::InvalidName),
                (7, ErrorCode::InvalidValue),
                (8, ErrorCode::InvalidName),
                (9, ErrorCode::InvalidQuantity),
            ]
        );
        assert_eq!(errors[0].message, "Jumlah harus berupa bilangan bulat.");
    }

    #[test]
    fn lines_invalid_carries_lines_in_details() {
        let err = lines_invalid(&[LineError::new(2, ErrorCode::InvalidPrice, "Harga salah.")]);
        assert_eq!(err.code(), ErrorCode::LinesInvalid);
        assert_eq!(err.status(), axum::http::StatusCode::UNPROCESSABLE_ENTITY);
        let line = serde_json::to_value(LineError::new(2, ErrorCode::InvalidPrice, "Harga salah."))
            .unwrap();
        assert_eq!(
            line,
            json!({"line_no": 2, "code": "invalid_price", "message": "Harga salah."})
        );
    }

    #[test]
    fn validate_reports_line_errors_sorted() {
        let err = request(json!([
            {"line_no": 5, "op": "sale", "product": "a", "quantity": 0},
            {"line_no": 2, "op": "sale", "product": "a", "quantity": 1.5},
        ]))
        .validate()
        .unwrap_err();
        assert_eq!(err.code(), ErrorCode::LinesInvalid);
    }
}
