//! Analytics JSON shapes. Money and quantities are whole numbers.

use serde::Serialize;

#[derive(Serialize)]
pub struct MonthRevenue {
    /// "YYYY-MM".
    pub month: String,
    pub revenue: i64,
}
