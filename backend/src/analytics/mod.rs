//! Laporan Analitik. Only completed transactions count and days are WIB.

pub mod dto;
pub mod handlers;

use std::collections::HashMap;

use rust_decimal::Decimal;
use rust_decimal::RoundingStrategy::MidpointAwayFromZero;
use rust_decimal::prelude::ToPrimitive;
use time::{Date, Duration};
use tokio_postgres::GenericClient;
use uuid::Uuid;

use crate::common::time::{
    Month, format_month, month_days_bounds, next_month, previous_month, same_days_previous_month,
    through_day, today_wib,
};
use crate::error::AppResult;
use dto::{MonthRevenue, MonthSummary, Previous, TopItem};

const TREND_MONTHS: usize = 12;
const TOP_ITEMS: i64 = 5;

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

/// Revenue and transaction count of days 1..=`days` of `month`.
async fn period(
    client: &impl GenericClient,
    user_id: Uuid,
    month: Month,
    days: u8,
) -> AppResult<(i64, i64)> {
    let end = month + Duration::days(days.into());
    let row = client
        .query_one(
            "SELECT COALESCE(sum(revenue), 0)::bigint AS revenue,
                    COALESCE(sum(transaction_count), 0)::bigint AS n
               FROM v_daily_sales WHERE user_id = $1 AND day >= $2 AND day < $3",
            &[&user_id, &month, &end],
        )
        .await?;
    Ok((row.get("revenue"), row.get("n")))
}

/// `(current - previous) / previous` as a percentage to one decimal, in
/// `Decimal` so no float rounding; `None` when `previous` is 0.
fn change_pct(current: i64, previous: i64) -> Option<f64> {
    if previous == 0 {
        return None;
    }
    (Decimal::from(current - previous) * Decimal::from(100) / Decimal::from(previous))
        .round_dp_with_strategy(1, MidpointAwayFromZero)
        .to_f64()
}

/// The 12 months ending with `month`, oldest first, zeros filled in.
async fn trend(
    client: &impl GenericClient,
    user_id: Uuid,
    month: Month,
) -> AppResult<Vec<MonthRevenue>> {
    let mut months = vec![month];
    for _ in 1..TREND_MONTHS {
        months.insert(0, previous_month(months[0]));
    }
    let rows = client
        .query(
            "SELECT date_trunc('month', day)::date AS month, sum(revenue)::bigint AS revenue
               FROM v_daily_sales
              WHERE user_id = $1 AND day >= $2 AND day < $3
              GROUP BY 1",
            &[&user_id, &months[0], &next_month(month)],
        )
        .await?;
    let by_month: HashMap<Date, i64> = rows
        .iter()
        .map(|r| (r.get("month"), r.get("revenue")))
        .collect();
    Ok(months
        .into_iter()
        .map(|m| MonthRevenue {
            month: format_month(m),
            revenue: by_month.get(&m).copied().unwrap_or(0),
        })
        .collect())
}

/// Best sellers of days 1..=`days` of `month`: by quantity, then revenue.
/// Grouped by product when it still exists (current name and stock), else by
/// the name snapshot on the item.
async fn top_items(
    client: &impl GenericClient,
    user_id: Uuid,
    month: Month,
    days: u8,
) -> AppResult<Vec<TopItem>> {
    let (start, end) = month_days_bounds(month, days);
    let rows = client
        .query(
            "SELECT COALESCE(p.name, max(i.product_name)) AS name,
                    sum(i.quantity) AS qty, sum(i.line_total)::bigint AS revenue, p.stock
               FROM transaction_items i
               JOIN transactions t ON t.id = i.transaction_id
               LEFT JOIN products p ON p.id = i.product_id
              WHERE t.user_id = $1 AND t.status = 'completed'
                AND t.occurred_at >= $2 AND t.occurred_at < $3
              GROUP BY i.product_id,
                       CASE WHEN i.product_id IS NULL THEN i.product_name END,
                       p.name, p.stock
              ORDER BY qty DESC, revenue DESC, name
              LIMIT $4",
            &[&user_id, &start, &end, &TOP_ITEMS],
        )
        .await?;
    let whole = |d: Decimal| d.to_i64().unwrap_or_default();
    Ok(rows
        .iter()
        .map(|r| TopItem {
            name: r.get("name"),
            qty: whole(r.get("qty")),
            revenue: r.get("revenue"),
            stock: r.get::<_, Option<Decimal>>("stock").map(whole),
        })
        .collect())
}

/// The month summary: days 1..=`through_day` against the same days of the
/// previous month, the 12-month trend and the best sellers.
pub async fn summary(
    client: &impl GenericClient,
    user_id: Uuid,
    month: Month,
) -> AppResult<MonthSummary> {
    let through = through_day(month, today_wib());
    let (revenue, transaction_count) = period(client, user_id, month, through).await?;
    let (prev_month, prev_days) = same_days_previous_month(month, through);
    let (prev_revenue, _) = period(client, user_id, prev_month, prev_days).await?;
    Ok(MonthSummary {
        month: format_month(month),
        through_day: through,
        revenue,
        transaction_count,
        previous: Previous {
            month: format_month(prev_month),
            revenue: prev_revenue,
            change_pct: change_pct(revenue, prev_revenue),
        },
        trend: trend(client, user_id, month).await?,
        weekday_avg: None,
        top_items: top_items(client, user_id, month, through).await?,
    })
}

#[cfg(test)]
mod tests {
    use super::change_pct;

    #[test]
    fn change_pct_rounds_to_one_decimal() {
        assert_eq!(change_pct(18_175_000, 16_800_000), Some(8.2));
        assert_eq!(change_pct(50, 100), Some(-50.0));
        assert_eq!(change_pct(1, 3), Some(-66.7));
        assert_eq!(change_pct(100, 0), None);
        assert_eq!(change_pct(0, 0), None);
    }
}
