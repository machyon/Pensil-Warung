//! Analytics JSON shapes. Money and quantities are whole numbers.

use serde::Serialize;

#[derive(Serialize)]
pub struct MonthRevenue {
    /// "YYYY-MM".
    pub month: String,
    pub revenue: i64,
}

#[derive(Serialize)]
pub struct Previous {
    pub month: String,
    pub revenue: i64,
    /// One decimal; `null` when the previous revenue is 0.
    pub change_pct: Option<f64>,
}

#[derive(Serialize)]
pub struct WeekdayAvg {
    /// 1 = Monday .. 7 = Sunday.
    pub weekday: i16,
    pub avg_revenue: i64,
}

#[derive(Serialize)]
pub struct TopItem {
    pub name: String,
    pub qty: i64,
    pub revenue: i64,
    /// Current stock; `null` once the product was deleted.
    pub stock: Option<i64>,
}

#[derive(Serialize)]
pub struct MonthSummary {
    pub month: String,
    pub through_day: u8,
    pub revenue: i64,
    pub transaction_count: i64,
    pub previous: Previous,
    /// 12 months, oldest first, ending with `month`.
    pub trend: Vec<MonthRevenue>,
    /// `null` while the month has fewer than 14 days with sales.
    pub weekday_avg: Option<Vec<WeekdayAvg>>,
    pub top_items: Vec<TopItem>,
}

#[derive(Serialize)]
pub struct DaySales {
    /// "YYYY-MM-DD" (WIB).
    pub day: String,
    pub transaction_count: i64,
    pub revenue: i64,
}

#[derive(Serialize)]
pub struct DayItem {
    pub product_id: Option<i64>,
    pub name: String,
    pub qty: i64,
    pub revenue: i64,
}

#[derive(Serialize)]
pub struct DayItems {
    /// Top 3 by quantity, then revenue.
    pub items: Vec<DayItem>,
    /// `total` minus the revenue of `items`.
    pub other_revenue: i64,
    /// Revenue of the whole day.
    pub total: i64,
}
