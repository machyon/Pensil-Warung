//! Name resolution across the batch. `plan` is pure: it walks the validated
//! ops in `line_no` order over a simulated copy of the user's products and
//! returns either an executable [`Plan`] or every line error found.
//!
//! The executor runs `steps` in order inside one transaction. It must not
//! look names up again and must take prices from the plan, never the client.

use std::collections::HashMap;

use rust_decimal::Decimal;

use super::ProductSnapshot;
use super::dto::{LineError, Op};
use crate::common::money::line_total;
use crate::common::names::name_key;
use crate::error::ErrorCode;

/// Which product a step acts on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProductRef {
    /// A product that already exists, by id.
    Existing(i64),
    /// The product made by the `CreateProduct` step with this `line_no`;
    /// the executor maps it to the id returned by `products::create`.
    Created(u32),
}

#[derive(Debug, Clone, PartialEq)]
pub enum Step {
    /// A transaction item. `unit_price` is the product's price when planned
    /// and `line_total = round(quantity * unit_price)`.
    Sale {
        line_no: u32,
        product: ProductRef,
        quantity: Decimal,
        unit_price: i64,
        line_total: i64,
    },
    /// Movement `restock`, `+quantity`.
    Restock {
        line_no: u32,
        product: ProductRef,
        quantity: Decimal,
    },
    /// Movement `adjustment`, `-quantity`.
    AdjustDown {
        line_no: u32,
        product: ProductRef,
        quantity: Decimal,
    },
    /// `products::set_price`.
    SetPrice {
        line_no: u32,
        product: ProductRef,
        price: i64,
    },
    /// `products::create`; `name` is already normalized and valid.
    CreateProduct {
        line_no: u32,
        name: String,
        price: i64,
        stock: i64,
    },
    /// `products::delete`. `photo_key` is the stored photo of an existing
    /// product, to delete from storage after commit (`None` when created in
    /// this batch or without photo).
    DeleteProduct {
        line_no: u32,
        product: ProductRef,
        photo_key: Option<String>,
    },
}

#[derive(Debug, PartialEq)]
pub struct Plan {
    /// In `line_no` order.
    pub steps: Vec<Step>,
    /// Sum of the `Sale` line totals. With no `Sale` step there is no
    /// transaction to insert.
    pub total: i64,
}

struct Sim {
    product: ProductRef,
    price: i64,
    stock: Decimal,
    photo_key: Option<String>,
}

/// `ops` must be sorted by `line_no` (as `Batch::ops` is). Every failing line
/// is reported and has no effect on the simulated state; the rest go on.
pub fn plan(ops: &[Op], products: Vec<ProductSnapshot>) -> Result<Plan, Vec<LineError>> {
    let mut state: HashMap<String, Sim> = products
        .into_iter()
        .map(|p| {
            let sim = Sim {
                product: ProductRef::Existing(p.id),
                price: p.price,
                stock: p.stock,
                photo_key: p.photo_key,
            };
            (p.name_key, sim)
        })
        .collect();
    let mut steps = Vec::with_capacity(ops.len());
    let mut errors = Vec::new();
    let mut total: i64 = 0;

    for op in ops {
        let line_no = op.line_no();
        let mut fail = |code, message: &str| errors.push(LineError::new(line_no, code, message));
        match op {
            Op::CreateProduct {
                name, price, stock, ..
            } => {
                let key = name_key(name);
                if state.contains_key(&key) {
                    fail(ErrorCode::NameTaken, "Nama produk sudah digunakan.");
                    continue;
                }
                state.insert(
                    key,
                    Sim {
                        product: ProductRef::Created(line_no),
                        price: *price,
                        stock: Decimal::from(*stock),
                        photo_key: None,
                    },
                );
                steps.push(Step::CreateProduct {
                    line_no,
                    name: name.clone(),
                    price: *price,
                    stock: *stock,
                });
            }
            Op::DeleteProduct { key, .. } => match state.remove(key) {
                Some(sim) => steps.push(Step::DeleteProduct {
                    line_no,
                    product: sim.product,
                    photo_key: sim.photo_key,
                }),
                None => fail(ErrorCode::ProductNotFound, "Produk tidak ditemukan."),
            },
            Op::Restock { key, quantity, .. } => match state.get_mut(key) {
                Some(sim) => {
                    sim.stock += quantity;
                    steps.push(Step::Restock {
                        line_no,
                        product: sim.product,
                        quantity: *quantity,
                    });
                }
                None => fail(ErrorCode::ProductNotFound, "Produk tidak ditemukan."),
            },
            Op::SetPrice { key, price, .. } => match state.get_mut(key) {
                Some(sim) => {
                    sim.price = *price;
                    steps.push(Step::SetPrice {
                        line_no,
                        product: sim.product,
                        price: *price,
                    });
                }
                None => fail(ErrorCode::ProductNotFound, "Produk tidak ditemukan."),
            },
            Op::AdjustDown { key, quantity, .. } | Op::Sale { key, quantity, .. } => {
                let Some(sim) = state.get_mut(key) else {
                    fail(ErrorCode::ProductNotFound, "Produk tidak ditemukan.");
                    continue;
                };
                if sim.stock < *quantity {
                    fail(ErrorCode::StockInsufficient, "Stok tidak cukup.");
                    continue;
                }
                if let Op::Sale { .. } = op {
                    let Some(lt) = line_total(*quantity, sim.price) else {
                        fail(ErrorCode::InvalidValue, "Total baris terlalu besar.");
                        continue;
                    };
                    let Some(new_total) = total.checked_add(lt) else {
                        fail(ErrorCode::InvalidValue, "Total transaksi terlalu besar.");
                        continue;
                    };
                    total = new_total;
                    steps.push(Step::Sale {
                        line_no,
                        product: sim.product,
                        quantity: *quantity,
                        unit_price: sim.price,
                        line_total: lt,
                    });
                } else {
                    steps.push(Step::AdjustDown {
                        line_no,
                        product: sim.product,
                        quantity: *quantity,
                    });
                }
                sim.stock -= quantity;
            }
        }
    }

    if errors.is_empty() {
        Ok(Plan { steps, total })
    } else {
        Err(errors)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::common::names::name_key;

    fn snap(id: i64, name: &str, price: i64, stock: i64) -> ProductSnapshot {
        ProductSnapshot {
            id,
            name_key: name_key(name),
            price,
            stock: Decimal::from(stock),
            photo_key: Some(format!("photo-{id}")),
        }
    }

    fn q(n: i64) -> Decimal {
        Decimal::from(n)
    }

    fn sale(line_no: u32, key: &str, n: i64) -> Op {
        Op::Sale {
            line_no,
            key: name_key(key),
            quantity: q(n),
        }
    }

    fn restock(line_no: u32, key: &str, n: i64) -> Op {
        Op::Restock {
            line_no,
            key: name_key(key),
            quantity: q(n),
        }
    }

    fn create(line_no: u32, name: &str, price: i64, stock: i64) -> Op {
        Op::CreateProduct {
            line_no,
            name: name.into(),
            price,
            stock,
        }
    }

    fn delete(line_no: u32, key: &str) -> Op {
        Op::DeleteProduct {
            line_no,
            key: name_key(key),
        }
    }

    fn errs(r: Result<Plan, Vec<LineError>>) -> Vec<(u32, ErrorCode)> {
        r.unwrap_err().iter().map(|e| (e.line_no, e.code)).collect()
    }

    #[test]
    fn sale_uses_product_price_and_sums_total() {
        let p = plan(
            &[sale(1, "nasi goreng", 2), sale(2, "es teh", 3)],
            vec![
                snap(1, "Nasi Goreng", 15_000, 10),
                snap(2, "Es Teh", 4_000, 10),
            ],
        )
        .unwrap();
        assert_eq!(p.total, 42_000);
        assert_eq!(
            p.steps[0],
            Step::Sale {
                line_no: 1,
                product: ProductRef::Existing(1),
                quantity: q(2),
                unit_price: 15_000,
                line_total: 30_000
            }
        );
    }

    #[test]
    fn name_matching_ignores_case_and_spaces() {
        let ops = [sale(1, "  NASI   goreng ", 1)];
        let p = plan(&ops, vec![snap(7, "Nasi goreng", 100, 1)]).unwrap();
        assert!(matches!(
            p.steps[0],
            Step::Sale {
                product: ProductRef::Existing(7),
                ..
            }
        ));
    }

    #[test]
    fn create_then_sell_refers_to_the_batch_product() {
        let p = plan(&[create(1, "Kopi", 5_000, 4), sale(2, "kopi", 3)], vec![]).unwrap();
        assert_eq!(p.total, 15_000);
        assert!(matches!(
            p.steps[1],
            Step::Sale {
                product: ProductRef::Created(1),
                unit_price: 5_000,
                ..
            }
        ));
    }

    #[test]
    fn create_with_existing_or_batch_name_is_name_taken() {
        let r = plan(
            &[
                create(1, "NASI goreng", 1, 0),
                create(2, "Kopi", 1, 0),
                create(3, "kopi", 1, 0),
            ],
            vec![snap(1, "Nasi goreng", 100, 1)],
        );
        assert_eq!(
            errs(r),
            [(1, ErrorCode::NameTaken), (3, ErrorCode::NameTaken)]
        );
    }

    #[test]
    fn delete_then_use_is_product_not_found() {
        let r = plan(
            &[
                delete(1, "nasi"),
                sale(2, "nasi", 1),
                restock(3, "nasi", 1),
                delete(4, "nasi"),
            ],
            vec![snap(1, "Nasi", 100, 5)],
        );
        assert_eq!(
            errs(r),
            [
                (2, ErrorCode::ProductNotFound),
                (3, ErrorCode::ProductNotFound),
                (4, ErrorCode::ProductNotFound)
            ]
        );
    }

    #[test]
    fn delete_carries_photo_key_and_frees_the_name() {
        let p = plan(
            &[
                delete(1, "nasi"),
                create(2, "Nasi", 200, 1),
                delete(3, "nasi"),
            ],
            vec![snap(1, "Nasi", 100, 5)],
        )
        .unwrap();
        assert_eq!(
            p.steps[0],
            Step::DeleteProduct {
                line_no: 1,
                product: ProductRef::Existing(1),
                photo_key: Some("photo-1".into())
            }
        );
        assert_eq!(
            p.steps[2],
            Step::DeleteProduct {
                line_no: 3,
                product: ProductRef::Created(2),
                photo_key: None
            }
        );
    }

    #[test]
    fn restock_first_makes_a_sale_fit() {
        let products = vec![snap(1, "Kopi", 1_000, 1)];
        assert_eq!(
            errs(plan(&[sale(1, "kopi", 5)], products.clone())),
            [(1, ErrorCode::StockInsufficient)]
        );
        let p = plan(&[restock(1, "kopi", 10), sale(2, "kopi", 5)], products).unwrap();
        assert_eq!(p.total, 5_000);
    }

    #[test]
    fn all_line_errors_are_reported() {
        let r = plan(
            &[
                sale(1, "kopi", 5),
                sale(2, "hantu", 1),
                Op::AdjustDown {
                    line_no: 3,
                    key: "kopi".into(),
                    quantity: q(2),
                },
                restock(4, "hantu", 1),
                sale(5, "kopi", 1),
            ],
            vec![snap(1, "Kopi", 1_000, 1)],
        );
        assert_eq!(
            errs(r),
            [
                (1, ErrorCode::StockInsufficient),
                (2, ErrorCode::ProductNotFound),
                (3, ErrorCode::StockInsufficient),
                (4, ErrorCode::ProductNotFound),
            ]
        );
    }

    #[test]
    fn same_product_on_two_lines_shares_stock_and_gives_two_items() {
        let products = vec![snap(1, "Kopi", 1_000, 5)];
        let p = plan(&[sale(1, "kopi", 3), sale(2, "kopi", 2)], products.clone()).unwrap();
        assert_eq!(p.steps.len(), 2);
        assert_eq!(p.total, 5_000);
        // 3 + 3 > 5: the second line is the short one, the first still counts.
        assert_eq!(
            errs(plan(&[sale(1, "kopi", 3), sale(2, "kopi", 3)], products)),
            [(2, ErrorCode::StockInsufficient)]
        );
    }

    #[test]
    fn failed_line_does_not_change_state() {
        // Line 1 fails, so line 2 still sees the full stock of 3.
        let r = plan(
            &[sale(1, "kopi", 4), sale(2, "kopi", 3)],
            vec![snap(1, "Kopi", 1, 3)],
        );
        assert_eq!(errs(r), [(1, ErrorCode::StockInsufficient)]);
    }

    #[test]
    fn adjust_down_reduces_stock_without_a_sale() {
        let p = plan(
            &[
                Op::AdjustDown {
                    line_no: 1,
                    key: "kopi".into(),
                    quantity: q(2),
                },
                sale(2, "kopi", 1),
            ],
            vec![snap(1, "Kopi", 1_000, 3)],
        )
        .unwrap();
        assert_eq!(p.total, 1_000);
        assert!(matches!(p.steps[0], Step::AdjustDown { .. }));
    }

    #[test]
    fn overflowing_line_total_is_a_line_error() {
        let r = plan(
            &[sale(1, "mahal", 999_999_999)],
            vec![ProductSnapshot {
                stock: q(999_999_999),
                ..snap(1, "Mahal", i64::MAX, 0)
            }],
        );
        assert_eq!(errs(r), [(1, ErrorCode::InvalidValue)]);
    }

    fn set_price(line_no: u32, key: &str, price: i64) -> Op {
        Op::SetPrice {
            line_no,
            key: name_key(key),
            price,
        }
    }

    #[test]
    fn set_price_applies_to_later_sales_only() {
        let p = plan(
            &[
                sale(1, "kopi", 1),
                set_price(2, "kopi", 2_000),
                sale(3, "kopi", 1),
            ],
            vec![snap(1, "Kopi", 1_000, 5)],
        )
        .unwrap();
        assert_eq!(p.total, 3_000);
        assert!(matches!(
            p.steps[0],
            Step::Sale {
                unit_price: 1_000,
                ..
            }
        ));
        assert!(matches!(p.steps[1], Step::SetPrice { price: 2_000, .. }));
        assert!(matches!(
            p.steps[2],
            Step::Sale {
                unit_price: 2_000,
                ..
            }
        ));
    }

    #[test]
    fn set_price_on_batch_product_and_unknown_or_deleted() {
        let p = plan(
            &[
                create(1, "Teh", 1_000, 5),
                set_price(2, "teh", 3_000),
                sale(3, "teh", 1),
            ],
            vec![],
        )
        .unwrap();
        assert_eq!(p.total, 3_000);
        assert!(matches!(
            p.steps[1],
            Step::SetPrice {
                product: ProductRef::Created(1),
                ..
            }
        ));
        let r = plan(
            &[
                set_price(1, "hantu", 1),
                delete(2, "kopi"),
                set_price(3, "kopi", 1),
            ],
            vec![snap(1, "Kopi", 1, 1)],
        );
        assert_eq!(
            errs(r),
            [
                (1, ErrorCode::ProductNotFound),
                (3, ErrorCode::ProductNotFound)
            ]
        );
    }

    #[test]
    fn no_sales_means_zero_total() {
        let p = plan(&[restock(1, "kopi", 1)], vec![snap(1, "Kopi", 1, 0)]).unwrap();
        assert_eq!(p.total, 0);
    }
}
