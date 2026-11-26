mod common;

use axum::http::StatusCode;
use backend::common::time::today_wib;
use common::{TestApp, TestResponse};
use rust_decimal::Decimal;
use serde_json::{Value, json};
use uuid::Uuid;

const URL: &str = "/api/v1/transactions";

async fn product(app: &TestApp, token: &str, name: &str, price: i64, stock: i64) -> i64 {
    let body = json!({"name": name, "price": price, "stock": stock});
    let res = app.post_json("/api/v1/products", Some(token), &body).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    res.json["id"].as_i64().unwrap()
}

/// One sale through POST /catat; `lines` are (product name, quantity). Returns the transaction id.
async fn sell(app: &TestApp, token: &str, lines: &[(&str, i64)]) -> i64 {
    let ops: Vec<Value> = lines
        .iter()
        .enumerate()
        .map(|(i, (p, q))| json!({"line_no": i + 1, "op": "sale", "product": p, "quantity": q}))
        .collect();
    let body = json!({"client_uuid": Uuid::new_v4(), "raw_text": "x", "ops": ops});
    let res = app.post_json("/api/v1/catat", Some(token), &body).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    res.json["transaction"]["id"].as_i64().unwrap()
}

async fn set_time(app: &TestApp, id: i64, at: &str) {
    app.client()
        .await
        .execute(
            "UPDATE transactions SET occurred_at = $2::text::timestamptz WHERE id = $1",
            &[&id, &at],
        )
        .await
        .unwrap();
}

async fn stock(app: &TestApp, id: i64) -> i64 {
    let d: Decimal = app
        .client()
        .await
        .query_one("SELECT stock FROM products WHERE id = $1", &[&id])
        .await
        .unwrap()
        .get(0);
    d.try_into().unwrap()
}

fn ids(res: &TestResponse) -> Vec<i64> {
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    res.json["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["id"].as_i64().unwrap())
        .collect()
}

async fn void(app: &TestApp, token: &str, id: i64, body: Value) -> TestResponse {
    app.post_json(&format!("{URL}/{id}/void"), Some(token), &body)
        .await
}

#[tokio::test]
async fn day_filter_uses_wib_boundaries_and_lists_newest_first() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    product(&app, &t, "Nasi goreng", 15000, 100).await;

    let a = sell(&app, &t, &[("Nasi goreng", 1)]).await;
    let b = sell(&app, &t, &[("Nasi goreng", 1)]).await;
    let c = sell(&app, &t, &[("Nasi goreng", 1)]).await;
    let d = sell(&app, &t, &[("Nasi goreng", 1)]).await;
    set_time(&app, a, "2026-11-16 16:59:59+00").await; // 23:59:59 WIB on the 16th
    set_time(&app, b, "2026-11-16 17:00:00+00").await; // 00:00:00 WIB on the 17th
    set_time(&app, c, "2026-11-17 16:59:59+00").await; // 23:59:59 WIB on the 17th
    set_time(&app, d, "2026-11-17 17:00:00+00").await; // 00:00:00 WIB on the 18th

    let day = |date: &str| format!("{URL}?date={date}");
    assert_eq!(ids(&app.get(&day("2026-11-16"), Some(&t)).await), [a]);
    assert_eq!(ids(&app.get(&day("2026-11-17"), Some(&t)).await), [c, b]);
    assert_eq!(ids(&app.get(&day("2026-11-18"), Some(&t)).await), [d]);
    assert!(ids(&app.get(&day("2026-11-19"), Some(&t)).await).is_empty());

    let res = app.get(&day("2026-11-17"), Some(&t)).await;
    assert_eq!(
        res.json["day"],
        json!({"date": "2026-11-17", "transaction_count": 2, "revenue": 30000})
    );
    assert_eq!(res.json["items"][0]["occurred_at"], "2026-11-17T16:59:59Z");

    // Default date is today in WIB.
    let e = sell(&app, &t, &[("Nasi goreng", 1)]).await;
    let res = app.get(URL, Some(&t)).await;
    assert_eq!(ids(&res), [e]);
    assert_eq!(res.json["day"]["date"], today_wib().to_string());

    for bad in ["2026-13-01", "17-11-2026", "abc", ""] {
        let res = app.get(&day(bad), Some(&t)).await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}");
        assert_eq!(res.json["error"]["code"], "invalid_value");
        assert_eq!(res.json["error"]["details"]["field"], "date");
    }
}

#[tokio::test]
async fn paging_walks_every_row_once_including_equal_timestamps() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    product(&app, &t, "Kopi", 5000, 100).await;
    let mut all = Vec::new();
    for _ in 0..7 {
        all.push(sell(&app, &t, &[("Kopi", 1)]).await);
    }
    // Four rows share one instant, so the id tiebreak decides their order.
    for (i, id) in all.iter().enumerate() {
        let at = if i < 4 {
            "2026-11-17 05:00:00+00"
        } else {
            &format!("2026-11-17 0{}:00:00+00", i - 3)
        };
        set_time(&app, *id, at).await;
    }
    let expected: Vec<i64> = app
        .client()
        .await
        .query(
            "SELECT id FROM transactions ORDER BY occurred_at DESC, id DESC",
            &[],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| r.get(0))
        .collect();

    let mut seen = Vec::new();
    let mut url = format!("{URL}?date=2026-11-17&limit=2");
    let mut pages = 0;
    loop {
        let res = app.get(&url, Some(&t)).await;
        seen.extend(ids(&res));
        if pages == 0 {
            assert_eq!(res.json["day"]["transaction_count"], 7);
        } else {
            assert!(res.json["day"].is_null(), "day only on the first page");
        }
        pages += 1;
        match res.json["next_cursor"].as_str() {
            Some(c) => url = format!("{URL}?date=2026-11-17&limit=2&cursor={c}"),
            None => break,
        }
    }
    assert_eq!(pages, 4);
    assert_eq!(seen, expected);

    let res = app
        .get(&format!("{URL}?date=2026-11-17&cursor=garbage"), Some(&t))
        .await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "invalid_value");
    assert_eq!(res.json["error"]["details"]["field"], "cursor");
}

#[tokio::test]
async fn items_have_count_summary_and_voided_sales_leave_the_day_totals() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    for (name, price) in [
        ("Nasi goreng", 15000),
        ("Es teh manis", 5000),
        ("Kopi", 4000),
        ("Teh", 3000),
    ] {
        product(&app, &t, name, price, 100).await;
    }
    let one = sell(&app, &t, &[("Nasi goreng", 2)]).await;
    let four = sell(
        &app,
        &t,
        &[
            ("Nasi goreng", 2),
            ("Es teh manis", 3),
            ("Kopi", 1),
            ("Teh", 1),
        ],
    )
    .await;
    let three = sell(&app, &t, &[("Kopi", 2), ("Teh", 1), ("Es teh manis", 1)]).await;
    set_time(&app, one, "2026-11-17 01:00:00+00").await;
    set_time(&app, four, "2026-11-17 02:00:00+00").await;
    set_time(&app, three, "2026-11-17 03:00:00+00").await;

    let res = app.get(&format!("{URL}?date=2026-11-17"), Some(&t)).await;
    let item = |i: usize, k: &str| res.json["items"][i][k].clone();
    assert_eq!(item(0, "id"), three);
    assert_eq!(item(0, "item_count"), 3);
    assert_eq!(item(0, "summary"), "Kopi 2, Teh 1, Es teh manis 1");
    assert_eq!(item(1, "item_count"), 4);
    assert_eq!(
        item(1, "summary"),
        "Nasi goreng 2, Es teh manis 3, Kopi 1 +1 lainnya"
    );
    assert_eq!(item(2, "summary"), "Nasi goreng 2");
    assert_eq!(item(2, "total"), 30000);
    assert_eq!(item(2, "status"), "completed");
    let total = 30000 + (30000 + 15000 + 4000 + 3000) + (8000 + 3000 + 5000);
    assert_eq!(res.json["day"]["revenue"], total);

    assert_eq!(void(&app, &t, four, json!({})).await.status, StatusCode::OK);
    let res = app.get(&format!("{URL}?date=2026-11-17"), Some(&t)).await;
    assert_eq!(ids(&res), [three, four, one]);
    assert_eq!(res.json["items"][1]["status"], "voided");
    assert_eq!(
        res.json["day"],
        json!({"date": "2026-11-17", "transaction_count": 2, "revenue": total - 52000})
    );
}

#[tokio::test]
async fn detail_is_scoped_to_the_owner() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let other = app
        .register("Budi", "budi@example.com", "password123")
        .await;
    product(&app, &t, "Kopi", 5000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 2)]).await;

    let res = app.get(&format!("{URL}/{id}"), Some(&t)).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["id"], id);
    assert_eq!(res.json["total"], 10000);
    assert_eq!(res.json["status"], "completed");
    assert_eq!(res.json["items"][0]["product_name"], "Kopi");
    assert_eq!(res.json["items"][0]["quantity"], 2);
    assert!(res.json["voided_at"].is_null());

    let res = app.get(&format!("{URL}/{id}"), Some(&other)).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    assert_eq!(res.json["error"]["code"], "not_found");
    assert_eq!(
        app.get(&format!("{URL}/999999"), Some(&t)).await.status,
        StatusCode::NOT_FOUND
    );
    // The other user's day list does not show it either.
    assert!(ids(&app.get(URL, Some(&other)).await).is_empty());
}

#[tokio::test]
async fn void_restores_stock_and_a_second_void_conflicts() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let other = app
        .register("Budi", "budi@example.com", "password123")
        .await;
    let p = product(&app, &t, "Kopi", 5000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 4)]).await;
    assert_eq!(stock(&app, p).await, 6);

    // Another user's sale is a 404 and is left alone.
    let res = void(&app, &other, id, json!({})).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    assert_eq!(stock(&app, p).await, 6);
    assert_eq!(
        void(&app, &t, 999_999, json!({})).await.status,
        StatusCode::NOT_FOUND
    );

    // A sale from long ago can still be voided, and the reason is trimmed.
    set_time(&app, id, "2020-01-01 00:00:00+00").await;
    let res = void(&app, &t, id, json!({"reason": "  salah catat  "})).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["status"], "voided");
    assert_eq!(res.json["void_reason"], "salah catat");
    assert!(res.json["voided_at"].is_string());
    assert_eq!(res.json["items"][0]["quantity"], 4);
    assert_eq!(stock(&app, p).await, 10);
    let movement: (String, i64) = {
        let r = app
            .client()
            .await
            .query_one(
                "SELECT reason::text, delta::bigint FROM stock_movements
                 WHERE product_id = $1 ORDER BY id DESC LIMIT 1",
                &[&p],
            )
            .await
            .unwrap();
        (r.get(0), r.get(1))
    };
    assert_eq!(movement, ("void_sale".to_owned(), 4));

    let res = void(&app, &t, id, json!({"reason": "lagi"})).await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    assert_eq!(res.json["error"]["code"], "already_voided");
    assert_eq!(stock(&app, p).await, 10);

    let detail = app.get(&format!("{URL}/{id}"), Some(&t)).await;
    assert_eq!(detail.json["status"], "voided");
    assert_eq!(detail.json["void_reason"], "salah catat");
}

#[tokio::test]
async fn void_reason_is_optional_trimmed_and_limited() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    product(&app, &t, "Kopi", 5000, 10).await;
    let a = sell(&app, &t, &[("Kopi", 1)]).await;
    let b = sell(&app, &t, &[("Kopi", 1)]).await;

    let res = void(&app, &t, a, json!({"reason": "x".repeat(201)})).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["details"]["field"], "reason");
    // Nothing was voided by the rejected request.
    let res = void(&app, &t, a, json!({"reason": "x".repeat(200)})).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);

    let res = void(&app, &t, b, json!({"reason": "   "})).await;
    assert_eq!(res.status, StatusCode::OK);
    assert!(res.json["void_reason"].is_null());
}

#[tokio::test]
async fn broadcaster_cannot_read_or_void_transactions() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    product(&app, &t, "Kopi", 5000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 1)]).await;
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

    for res in [
        app.get(URL, Some(&b)).await,
        app.get(&format!("{URL}/{id}"), Some(&b)).await,
        void(&app, &b, id, json!({})).await,
    ] {
        assert_eq!(res.status, StatusCode::FORBIDDEN, "{}", res.text);
        assert_eq!(res.json["error"]["code"], "forbidden");
    }
    assert_eq!(app.get(URL, None).await.status, StatusCode::UNAUTHORIZED);
    // Still completed.
    let res = app.get(&format!("{URL}/{id}"), Some(&t)).await;
    assert_eq!(res.json["status"], "completed");
}
