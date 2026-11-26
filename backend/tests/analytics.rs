mod common;

use axum::http::StatusCode;
use common::TestApp;
use serde_json::{Value, json};
use uuid::Uuid;

const URL: &str = "/api/v1/analytics";

async fn product(app: &TestApp, token: &str, name: &str, price: i64, stock: i64) -> i64 {
    let body = json!({"name": name, "price": price, "stock": stock});
    let res = app.post_json("/api/v1/products", Some(token), &body).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    res.json["id"].as_i64().unwrap()
}

/// One sale through POST /catat at `at` (RFC 3339, moved with SQL); `lines` are (product, qty).
async fn sell_at(app: &TestApp, token: &str, at: &str, lines: &[(&str, i64)]) -> i64 {
    let ops: Vec<Value> = lines
        .iter()
        .enumerate()
        .map(|(i, (p, q))| json!({"line_no": i + 1, "op": "sale", "product": p, "quantity": q}))
        .collect();
    let body = json!({"client_uuid": Uuid::new_v4(), "raw_text": "x", "ops": ops});
    let res = app.post_json("/api/v1/catat", Some(token), &body).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let id = res.json["transaction"]["id"].as_i64().unwrap();
    app.client()
        .await
        .execute(
            "UPDATE transactions SET occurred_at = $2::text::timestamptz WHERE id = $1",
            &[&id, &at],
        )
        .await
        .unwrap();
    id
}

async fn get(app: &TestApp, token: &str, path: &str) -> Value {
    let res = app.get(&format!("{URL}{path}"), Some(token)).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    res.json
}

async fn user_with_nasi(app: &TestApp) -> String {
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    product(app, &t, "Nasi goreng", 10000, 1000).await;
    t
}

#[tokio::test]
async fn months_are_newest_first_wib_grouped_and_skip_voided() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    assert_eq!(get(&app, &t, "/months").await, json!([]));

    sell_at(&app, &t, "2026-09-10T03:00:00Z", &[("Nasi goreng", 1)]).await;
    // 17:30 UTC on 31 Oct is already 1 Nov in WIB.
    sell_at(&app, &t, "2026-10-31T17:30:00Z", &[("Nasi goreng", 2)]).await;
    sell_at(&app, &t, "2026-11-02T03:00:00Z", &[("Nasi goreng", 3)]).await;
    let voided = sell_at(&app, &t, "2026-12-01T03:00:00Z", &[("Nasi goreng", 5)]).await;
    let res = app
        .post_json(
            &format!("/api/v1/transactions/{voided}/void"),
            Some(&t),
            &json!({}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);

    assert_eq!(
        get(&app, &t, "/months").await,
        json!([
            {"month": "2026-11", "revenue": 50000},
            {"month": "2026-09", "revenue": 10000},
        ])
    );

    let other = app
        .register("Budi", "budi@example.com", "password123")
        .await;
    assert_eq!(get(&app, &other, "/months").await, json!([]));
    let res = app.get(&format!("{URL}/months"), None).await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn summary_compares_the_same_days_and_zero_fills_the_trend() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    // Past month 2026-03: through_day is 31, previous is Feb 2026 (28 days, clamped).
    sell_at(&app, &t, "2026-03-05T03:00:00Z", &[("Nasi goreng", 4)]).await; // 40000
    sell_at(&app, &t, "2026-03-31T03:00:00Z", &[("Nasi goreng", 1)]).await; // 10000
    sell_at(&app, &t, "2026-02-28T03:00:00Z", &[("Nasi goreng", 2)]).await; // 20000
    sell_at(&app, &t, "2026-02-01T03:00:00Z", &[("Nasi goreng", 1)]).await; // 10000
    sell_at(&app, &t, "2025-05-10T03:00:00Z", &[("Nasi goreng", 7)]).await; // before the 12 months

    let j = get(&app, &t, "/month?month=2026-03").await;
    assert_eq!(j["month"], "2026-03");
    assert_eq!(j["through_day"], 31);
    assert_eq!(j["revenue"], 50000);
    assert_eq!(j["transaction_count"], 2);
    assert_eq!(
        j["previous"],
        json!({"month": "2026-02", "revenue": 30000, "change_pct": 66.7})
    );
    assert_eq!(j["weekday_avg"], Value::Null);
    let trend = j["trend"].as_array().unwrap();
    assert_eq!(trend.len(), 12);
    assert_eq!(trend[0], json!({"month": "2025-04", "revenue": 0}));
    assert_eq!(trend[9], json!({"month": "2026-01", "revenue": 0}));
    assert_eq!(trend[10], json!({"month": "2026-02", "revenue": 30000}));
    assert_eq!(trend[11], json!({"month": "2026-03", "revenue": 50000}));

    // An empty month: zeros, and no percentage against a zero previous month.
    let j = get(&app, &t, "/month?month=2024-01").await;
    assert_eq!(j["revenue"], 0);
    assert_eq!(j["previous"]["change_pct"], Value::Null);
    assert_eq!(j["top_items"], json!([]));
}

#[tokio::test]
async fn top_items_group_by_product_and_fall_back_to_the_snapshot_name() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    let teh = product(&app, &t, "Es teh", 5000, 20).await;
    sell_at(
        &app,
        &t,
        "2026-03-05T03:00:00Z",
        &[("Nasi goreng", 2), ("Es teh", 3)],
    )
    .await;
    sell_at(&app, &t, "2026-03-06T03:00:00Z", &[("Nasi goreng", 2)]).await;
    // Renamed products group under the current name.
    let res = app
        .patch_json(
            &format!("/api/v1/products/{teh}"),
            Some(&t),
            &json!({"name": "Teh manis"}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);

    let j = get(&app, &t, "/month?month=2026-03").await;
    assert_eq!(
        j["top_items"],
        json!([
            {"name": "Nasi goreng", "qty": 4, "revenue": 40000, "stock": 996},
            {"name": "Teh manis", "qty": 3, "revenue": 15000, "stock": 17},
        ])
    );

    // Delete the product: it now groups by the name on the sale and has no stock.
    let res = app
        .delete_json(&format!("/api/v1/products/{teh}"), Some(&t), None)
        .await;
    assert!(res.status.is_success(), "{}", res.text);
    let j = get(&app, &t, "/month?month=2026-03").await;
    let items = j["top_items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[1]["name"], "Es teh");
    assert_eq!(items[1]["qty"], 3);
    assert_eq!(items[1]["stock"], Value::Null);
}

#[tokio::test]
async fn bad_or_future_month_is_422() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    for m in ["2999-01", "nope", "2026-13"] {
        let res = app.get(&format!("{URL}/month?month={m}"), Some(&t)).await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{m}");
        assert_eq!(res.json["error"]["code"], "invalid_value");
        assert_eq!(res.json["error"]["details"]["field"], "month");
    }
    // The current month is the default and always allowed.
    let j = get(&app, &t, "/month").await;
    assert_eq!(j["trend"].as_array().unwrap().len(), 12);
}

#[tokio::test]
async fn weekday_avg_needs_14_sales_days_and_counts_empty_days() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    // Rp10.000 a day on 1..=13 March 2026 (1 Mar is a Sunday).
    for day in 1..=13 {
        sell_at(
            &app,
            &t,
            &format!("2026-03-{day:02}T03:00:00Z"),
            &[("Nasi goreng", 1)],
        )
        .await;
    }
    let j = get(&app, &t, "/month?month=2026-03").await;
    assert_eq!(j["weekday_avg"], Value::Null);

    sell_at(&app, &t, "2026-03-14T03:00:00Z", &[("Nasi goreng", 1)]).await;
    let j = get(&app, &t, "/month?month=2026-03").await;
    // Each weekday sold twice (Rp20.000) in days 1..=14. March has 5 Sun/Mon/Tue
    // and 4 of the others, and the empty days after the 14th count as Rp0.
    let avg: Vec<(i64, i64)> = j["weekday_avg"]
        .as_array()
        .unwrap()
        .iter()
        .map(|w| {
            (
                w["weekday"].as_i64().unwrap(),
                w["avg_revenue"].as_i64().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        avg,
        [
            (1, 4000),
            (2, 4000),
            (3, 5000),
            (4, 5000),
            (5, 5000),
            (6, 5000),
            (7, 4000)
        ]
    );
}
