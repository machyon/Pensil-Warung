//! Laporan Analitik. Only completed transactions count and days are WIB.

pub mod dto;
pub mod handlers;

use time::Date;
use tokio_postgres::GenericClient;
use uuid::Uuid;

use crate::common::time::format_month;
use crate::error::AppResult;
use dto::MonthRevenue;

/// Months with completed sales, newest first.
pub async fn months(client: &impl GenericClient, user_id: Uuid) -> AppResult<Vec<MonthRevenue>> {
    let rows = client
        .query(
            "SELECT date_trunc('month', day)::date AS month, sum(revenue)::bigint AS revenue
               FROM v_daily_sales WHERE user_id = $1
              GROUP BY 1 ORDER BY 1 DESC",
            &[&user_id],
        )
        .await?;
    Ok(rows
        .iter()
        .map(|r| MonthRevenue {
            month: format_month(r.get::<_, Date>("month")),
            revenue: r.get("revenue"),
        })
        .collect())
}
