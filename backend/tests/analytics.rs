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
    let items = j["top_items"].as_array().unwrap();
    assert!(items[0]["product_id"].is_i64());
    assert_eq!(items[1]["product_id"], teh);
    assert_eq!(
        items
            .iter()
            .map(|i| (&i["name"], &i["qty"], &i["revenue"], &i["stock"]))
            .collect::<Vec<_>>(),
        [
            (&json!("Nasi goreng"), &json!(4), &json!(40000), &json!(996)),
            (&json!("Teh manis"), &json!(3), &json!(15000), &json!(17)),
        ]
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
    assert_eq!(items[1]["product_id"], Value::Null);
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

async fn void(app: &TestApp, token: &str, id: i64) {
    let res = app
        .post_json(
            &format!("/api/v1/transactions/{id}/void"),
            Some(token),
            &json!({}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
}

async fn get_err(app: &TestApp, token: &str, path: &str, field: &str) {
    let res = app.get(&format!("{URL}{path}"), Some(token)).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{path}");
    assert_eq!(res.json["error"]["code"], "invalid_value");
    assert_eq!(res.json["error"]["details"]["field"], field);
}

#[tokio::test]
async fn days_list_pages_newest_first_on_wib_days_and_skips_voided() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    // 16:59:59 UTC is still the 9th in WIB; 17:00:00 UTC is the 10th.
    sell_at(&app, &t, "2026-03-09T16:59:59Z", &[("Nasi goreng", 1)]).await;
    sell_at(&app, &t, "2026-03-09T17:00:00Z", &[("Nasi goreng", 2)]).await;
    sell_at(&app, &t, "2026-03-10T03:00:00Z", &[("Nasi goreng", 3)]).await;
    for day in [1, 20, 31] {
        sell_at(
            &app,
            &t,
            &format!("2026-03-{day:02}T03:00:00Z"),
            &[("Nasi goreng", 1)],
        )
        .await;
    }
    // Another month, and a voided-only day, must not show up.
    sell_at(&app, &t, "2026-04-01T03:00:00Z", &[("Nasi goreng", 1)]).await;
    let v = sell_at(&app, &t, "2026-03-15T03:00:00Z", &[("Nasi goreng", 9)]).await;
    void(&app, &t, v).await;

    let all = get(&app, &t, "/month/days?month=2026-03").await;
    assert_eq!(all["next_cursor"], Value::Null);
    assert_eq!(
        all["items"],
        json!([
            {"day": "2026-03-31", "transaction_count": 1, "revenue": 10000},
            {"day": "2026-03-20", "transaction_count": 1, "revenue": 10000},
            {"day": "2026-03-10", "transaction_count": 2, "revenue": 50000},
            {"day": "2026-03-09", "transaction_count": 1, "revenue": 10000},
            {"day": "2026-03-01", "transaction_count": 1, "revenue": 10000},
        ])
    );

    // Walk every page with limit 2: no day twice, none missing.
    let mut seen = vec![];
    let mut path = "/month/days?month=2026-03&limit=2".to_owned();
    loop {
        let page = get(&app, &t, &path).await;
        for d in page["items"].as_array().unwrap() {
            seen.push(d["day"].as_str().unwrap().to_owned());
        }
        match page["next_cursor"].as_str() {
            Some(c) => path = format!("/month/days?month=2026-03&limit=2&cursor={c}"),
            None => break,
        }
    }
    assert_eq!(
        seen,
        [
            "2026-03-31",
            "2026-03-20",
            "2026-03-10",
            "2026-03-09",
            "2026-03-01"
        ]
    );

    get_err(
        &app,
        &t,
        "/month/days?month=2026-03&cursor=%21%21",
        "cursor",
    )
    .await;
    get_err(&app, &t, "/month/days?month=2999-01", "month").await;
}

#[tokio::test]
async fn day_items_show_top_3_other_revenue_and_wib_bounds() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    for (n, p) in [("Es teh", 5000), ("Kopi", 4000), ("Roti", 3000)] {
        product(&app, &t, n, p, 100).await;
    }
    sell_at(
        &app,
        &t,
        "2026-03-09T20:00:00Z", // 10 March 03:00 WIB
        &[("Nasi goreng", 5), ("Es teh", 4), ("Kopi", 3), ("Roti", 1)],
    )
    .await;
    // Outside the WIB day on both sides.
    sell_at(&app, &t, "2026-03-09T16:59:59Z", &[("Nasi goreng", 7)]).await;
    sell_at(&app, &t, "2026-03-10T17:00:00Z", &[("Nasi goreng", 7)]).await;
    let v = sell_at(&app, &t, "2026-03-10T03:00:00Z", &[("Nasi goreng", 9)]).await;
    void(&app, &t, v).await;

    let j = get(&app, &t, "/days/2026-03-10/items").await;
    assert_eq!(j["total"], 85000);
    assert_eq!(j["other_revenue"], 3000);
    let names: Vec<&str> = j["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["Nasi goreng", "Es teh", "Kopi"]);
    assert_eq!(j["items"][0]["qty"], 5);
    assert_eq!(j["items"][0]["revenue"], 50000);
    assert!(j["items"][0]["product_id"].is_i64());

    // One product only: nothing left over.
    let j = get(&app, &t, "/days/2026-03-09/items").await;
    assert_eq!(j["total"], 70000);
    assert_eq!(j["other_revenue"], 0);

    let j = get(&app, &t, "/days/2026-01-01/items").await;
    assert_eq!(j, json!({"items": [], "other_revenue": 0, "total": 0}));

    for bad in ["nope", "2026-13-01", "2999-01-01"] {
        get_err(&app, &t, &format!("/days/{bad}/items"), "date").await;
    }
}

#[tokio::test]
async fn month_items_share_q_and_unsold() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    for (n, p) in [("Es teh", 5000), ("Kopi susu", 4000), ("Roti", 3000)] {
        product(&app, &t, n, p, 100).await;
    }
    // Kopi susu sells only in April, Roti never.
    sell_at(
        &app,
        &t,
        "2026-03-05T03:00:00Z",
        &[("Nasi goreng", 2), ("Es teh", 1)],
    )
    .await;
    sell_at(&app, &t, "2026-03-06T03:00:00Z", &[("Es teh", 1)]).await;
    sell_at(&app, &t, "2026-04-06T03:00:00Z", &[("Kopi susu", 1)]).await;
    let v = sell_at(&app, &t, "2026-03-07T03:00:00Z", &[("Roti", 5)]).await;
    void(&app, &t, v).await;

    let j = get(&app, &t, "/month/items?month=2026-03").await;
    assert_eq!(j["total_qty"], 4);
    assert_eq!(j["revenue"], 30000);
    let items = j["items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    // Ranked by qty: 2 Nasi goreng, 2 Es teh (revenue breaks the tie).
    assert_eq!(items[0]["name"], "Nasi goreng");
    assert_eq!(items[0]["share_pct"], 50.0);
    assert_eq!(items[0]["stock"], 998);
    assert_eq!(items[1]["name"], "Es teh");
    let pct: f64 = items.iter().map(|i| i["share_pct"].as_f64().unwrap()).sum();
    assert!((pct - 100.0).abs() < 0.2);
    let unsold: Vec<&str> = j["unsold"]
        .as_array()
        .unwrap()
        .iter()
        .map(|u| u["name"].as_str().unwrap())
        .collect();
    assert_eq!(unsold, ["Kopi susu", "Roti"]);
    assert_eq!(j["unsold"][1]["stock"], 100); // voided sale restored stock

    // q narrows both lists (case-insensitive) but not the whole-month figures.
    let j = get(&app, &t, "/month/items?month=2026-03&q=TEH").await;
    assert_eq!(
        (j["total_qty"].clone(), j["revenue"].clone()),
        (json!(4), json!(30000))
    );
    assert_eq!(j["items"].as_array().unwrap().len(), 1);
    assert_eq!(j["items"][0]["name"], "Es teh");
    assert_eq!(j["items"][0]["share_pct"], 50.0);
    assert_eq!(j["unsold"], json!([]));
    let j = get(&app, &t, "/month/items?month=2026-03&q=ro").await;
    assert_eq!(j["items"], json!([]));
    assert_eq!(j["unsold"].as_array().unwrap().len(), 1);
    // `%` is literal.
    let j = get(&app, &t, "/month/items?month=2026-03&q=%25").await;
    assert_eq!(
        (j["items"].clone(), j["unsold"].clone()),
        (json!([]), json!([]))
    );
}

#[tokio::test]
async fn deleted_product_groups_by_snapshot_in_item_endpoints() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    let teh = product(&app, &t, "Es teh", 5000, 20).await;
    sell_at(&app, &t, "2026-03-05T03:00:00Z", &[("Es teh", 2)]).await;
    sell_at(
        &app,
        &t,
        "2026-03-05T04:00:00Z",
        &[("Es teh", 1), ("Nasi goreng", 1)],
    )
    .await;
    let res = app
        .delete_json(&format!("/api/v1/products/{teh}"), Some(&t), None)
        .await;
    assert!(res.status.is_success(), "{}", res.text);
    // A new product with the same name is a different group.
    product(&app, &t, "Es teh", 5000, 20).await;
    sell_at(&app, &t, "2026-03-06T03:00:00Z", &[("Es teh", 1)]).await;

    let j = get(&app, &t, "/month/items?month=2026-03").await;
    let items = j["items"].as_array().unwrap();
    assert_eq!(items.len(), 3);
    assert_eq!(items[0]["name"], "Es teh");
    assert_eq!(items[0]["qty"], 3);
    assert_eq!(items[0]["product_id"], Value::Null);
    assert_eq!(items[0]["stock"], Value::Null);
    assert!(items[2]["product_id"].is_i64());
    assert_eq!(j["total_qty"], 5);

    let j = get(&app, &t, "/days/2026-03-05/items").await;
    assert_eq!(j["items"][0]["name"], "Es teh");
    assert_eq!(j["items"][0]["qty"], 3);
    assert_eq!(j["items"][0]["product_id"], Value::Null);
}

#[tokio::test]
async fn empty_month_has_zeros_and_empty_lists() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    let j = get(&app, &t, "/month/items?month=2024-01").await;
    assert_eq!(j["total_qty"], 0);
    assert_eq!(j["revenue"], 0);
    assert_eq!(j["items"], json!([]));
    assert_eq!(j["unsold"].as_array().unwrap().len(), 1); // Nasi goreng
    let j = get(&app, &t, "/month/days?month=2024-01").await;
    assert_eq!(j, json!({"items": [], "next_cursor": null}));
}

#[tokio::test]
async fn analytics_are_private_and_need_the_permission() {
    let app = TestApp::new().await;
    let t = user_with_nasi(&app).await;
    sell_at(&app, &t, "2026-03-05T03:00:00Z", &[("Nasi goreng", 2)]).await;
    let other = app
        .register("Budi", "budi@example.com", "password123")
        .await;
    for path in [
        "/month/days?month=2026-03",
        "/days/2026-03-05/items",
        "/month/items?month=2026-03",
    ] {
        let j = get(&app, &other, path).await;
        assert!(
            j["items"] == json!([]) && j.get("total").is_none_or(|v| v == 0),
            "{path}: {j}"
        );
    }
    assert_eq!(
        get(&app, &other, "/month/items?month=2026-03").await["total_qty"],
        0
    );

    let uid: Uuid = app
        .client()
        .await
        .query_one("SELECT id FROM users WHERE email = 'siti@example.com'", &[])
        .await
        .unwrap()
        .get(0);
    // Same user, but the token carries the seeded `broadcaster` role (id 2).
    let b = backend::auth::jwt::issue_token(
        &app.config.jwt_secret,
        uid,
        2,
        0,
        app.config.jwt_expires_in,
    )
    .unwrap();
    for path in [
        "/months",
        "/month",
        "/month/days",
        "/month/items",
        "/days/2026-03-05/items",
    ] {
        let res = app.get(&format!("{URL}{path}"), Some(&b)).await;
        assert_eq!(res.status, StatusCode::FORBIDDEN, "{path}");
        let res = app.get(&format!("{URL}{path}"), None).await;
        assert_eq!(res.status, StatusCode::UNAUTHORIZED, "{path}");
    }
}
