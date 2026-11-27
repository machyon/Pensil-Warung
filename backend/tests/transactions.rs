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

#[tokio::test]
async fn void_accepts_an_empty_body_and_rejects_bad_json() {
    use axum::body::Body;
    use axum::http::{Method, Request};
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    product(&app, &t, "Kopi", 5000, 10).await;
    let a = sell(&app, &t, &[("Kopi", 1)]).await;
    let b = sell(&app, &t, &[("Kopi", 1)]).await;
    let post = |id: i64, ct: Option<&str>, body: &str| {
        let mut r = Request::builder()
            .method(Method::POST)
            .uri(format!("{URL}/{id}/void"))
            .header("authorization", format!("Bearer {t}"));
        if let Some(ct) = ct {
            r = r.header("content-type", ct);
        }
        r.body(Body::from(body.to_owned())).unwrap()
    };

    for bad in [
        (Some("application/json"), "{oops"),
        (Some("text/plain"), "hello"),
    ] {
        let res = app.send(post(a, bad.0, bad.1)).await;
        assert_eq!(res.status, StatusCode::BAD_REQUEST, "{}", res.text);
        assert_eq!(res.json["error"]["code"], "invalid_body");
    }
    let res = app.send(post(a, None, "")).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert!(res.json["void_reason"].is_null());
    let res = app.send(post(b, Some("application/json"), "")).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
}

// ---- revise ----

async fn revise(app: &TestApp, token: &str, id: i64, uuid: Uuid, items: Value) -> TestResponse {
    app.post_json(
        &format!("{URL}/{id}/revise"),
        Some(token),
        &json!({"client_uuid": uuid, "items": items}),
    )
    .await
}

async fn detail(app: &TestApp, token: &str, id: i64) -> Value {
    let res = app.get(&format!("{URL}/{id}"), Some(token)).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    res.json
}

fn item_id(t: &Value, line: usize) -> i64 {
    t["items"][line]["id"].as_i64().unwrap()
}

fn line_errors(res: &TestResponse) -> Vec<(i64, String)> {
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{}", res.text);
    assert_eq!(res.json["error"]["code"], "lines_invalid");
    res.json["error"]["details"]["lines"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| {
            (
                l["line_no"].as_i64().unwrap(),
                l["code"].as_str().unwrap().to_owned(),
            )
        })
        .collect()
}

#[tokio::test]
async fn revise_keeps_snapshots_restores_then_takes_stock_and_chains_history() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let nasi = product(&app, &t, "Nasi goreng", 10000, 10).await;
    let teh = product(&app, &t, "Es teh", 2000, 5).await;
    let kopi = product(&app, &t, "Kopi", 5000, 1).await;
    let first = sell(&app, &t, &[("Nasi goreng", 2), ("Es teh", 1)]).await;
    set_time(&app, first, "2026-11-17 03:00:00+00").await;
    // The product price moves after the sale; the old item keeps its snapshot.
    app.client()
        .await
        .execute("UPDATE products SET price = 12000 WHERE id = $1", &[&nasi])
        .await
        .unwrap();
    assert_eq!((stock(&app, nasi).await, stock(&app, teh).await), (8, 4));
    let old = detail(&app, &t, first).await;
    assert_eq!(old["replaces_id"], Value::Null);
    assert_eq!(old["replaced_by_id"], Value::Null);
    assert_eq!(old["history"], json!([]));

    // Nasi 2 -> 3, Es teh removed, Kopi (stock 1) added at its current price.
    let res = revise(
        &app,
        &t,
        first,
        Uuid::new_v4(),
        json!([{"item_id": item_id(&old, 0), "quantity": 3}, {"product_id": kopi, "quantity": 1}]),
    )
    .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let second = res.json["id"].as_i64().unwrap();
    assert_eq!(res.json["status"], "completed");
    assert_eq!(res.json["occurred_at"], "2026-11-17T03:00:00Z");
    assert_eq!(res.json["raw_text"], "Nasi goreng 3\nKopi 1");
    assert_eq!(res.json["total"], 3 * 10000 + 5000);
    assert_eq!(res.json["replaces_id"], first);
    assert_eq!(res.json["replaced_by_id"], Value::Null);
    let items = res.json["items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(
        (
            items[0]["line_no"].as_i64(),
            items[0]["unit_price"].as_i64()
        ),
        (Some(1), Some(10000))
    );
    assert_eq!(items[0]["product_id"], nasi);
    assert_eq!(
        (
            items[1]["line_no"].as_i64(),
            items[1]["unit_price"].as_i64()
        ),
        (Some(2), Some(5000))
    );
    assert_eq!(res.json["history"].as_array().unwrap().len(), 1);
    assert_eq!(res.json["history"][0]["id"], first);
    assert_eq!(res.json["history"][0]["raw_text"], "x");
    assert_eq!(res.json["history"][0]["items"].as_array().unwrap().len(), 2);
    assert!(res.json["history"][0]["revised_at"].is_string());
    // 10 - 3, Es teh restored to 5, Kopi taken.
    assert_eq!(
        (
            stock(&app, nasi).await,
            stock(&app, teh).await,
            stock(&app, kopi).await
        ),
        (7, 5, 0)
    );

    // The replaced row is voided, points forward, and leaves the day list.
    let old = detail(&app, &t, first).await;
    assert_eq!(old["status"], "voided");
    assert_eq!(old["replaced_by_id"], second);
    let day = app.get(&format!("{URL}?date=2026-11-17"), Some(&t)).await;
    assert_eq!(ids(&day), [second]);
    assert_eq!(day.json["day"]["transaction_count"], 1);
    assert_eq!(day.json["day"]["revenue"], 35000);

    // Revise the revision: history has both older versions, newest first.
    let cur = detail(&app, &t, second).await;
    let res = revise(
        &app,
        &t,
        second,
        Uuid::new_v4(),
        json!([{"item_id": item_id(&cur, 0), "quantity": 1}]),
    )
    .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let third = res.json["id"].as_i64().unwrap();
    let hist: Vec<i64> = res.json["history"]
        .as_array()
        .unwrap()
        .iter()
        .map(|h| h["id"].as_i64().unwrap())
        .collect();
    assert_eq!(hist, [second, first]);
    assert_eq!(
        detail(&app, &t, third).await["history"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    assert_eq!(stock(&app, kopi).await, 1);
    assert_eq!(stock(&app, nasi).await, 9);

    // A replaced row cannot be revised or cancelled again.
    for id in [first, second] {
        let res = revise(
            &app,
            &t,
            id,
            Uuid::new_v4(),
            json!([{"product_id": kopi, "quantity": 1}]),
        )
        .await;
        assert_eq!(res.status, StatusCode::CONFLICT, "{}", res.text);
        assert_eq!(res.json["error"]["code"], "already_voided");
    }
}

#[tokio::test]
async fn cancelled_row_has_no_replacement_and_cannot_be_revised() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let kopi = product(&app, &t, "Kopi", 5000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 1)]).await;
    assert_eq!(void(&app, &t, id, json!({})).await.status, StatusCode::OK);
    let d = detail(&app, &t, id).await;
    assert_eq!(d["status"], "voided");
    assert_eq!(d["replaced_by_id"], Value::Null);
    let res = revise(
        &app,
        &t,
        id,
        Uuid::new_v4(),
        json!([{"product_id": kopi, "quantity": 1}]),
    )
    .await;
    assert_eq!(res.status, StatusCode::CONFLICT, "{}", res.text);
    assert_eq!(res.json["error"]["code"], "already_voided");
}

#[tokio::test]
async fn revise_retry_returns_the_same_transaction_and_no_changes_is_422() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let kopi = product(&app, &t, "Kopi", 5000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 2)]).await;
    let old = detail(&app, &t, id).await;
    let keep = |q: i64| json!([{"item_id": item_id(&old, 0), "quantity": q}]);

    let res = revise(&app, &t, id, Uuid::new_v4(), keep(2)).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{}", res.text);
    assert_eq!(res.json["error"]["code"], "no_changes");
    assert_eq!(detail(&app, &t, id).await["status"], "completed");

    let uuid = Uuid::new_v4();
    let a = revise(&app, &t, id, uuid, keep(5)).await;
    assert_eq!(a.status, StatusCode::CREATED, "{}", a.text);
    let b = revise(&app, &t, id, uuid, keep(5)).await;
    assert_eq!(b.status, StatusCode::OK, "{}", b.text);
    assert_eq!(a.json["id"], b.json["id"]);
    assert_eq!(stock(&app, kopi).await, 5);
    let n: i64 = app
        .client()
        .await
        .query_one("SELECT count(*) FROM transactions", &[])
        .await
        .unwrap()
        .get(0);
    assert_eq!(n, 2);
}

#[tokio::test]
async fn revise_collects_line_errors_with_one_based_line_numbers() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let other = app
        .register("Budi", "budi@example.com", "password123")
        .await;
    let kopi = product(&app, &t, "Kopi", 5000, 10).await;
    let teh = product(&app, &t, "Teh", 2000, 3).await;
    let foreign = product(&app, &other, "Gula", 1000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 2)]).await;
    let old = detail(&app, &t, id).await;
    let k = item_id(&old, 0);

    let res = revise(
        &app,
        &t,
        id,
        Uuid::new_v4(),
        json!([
            {"item_id": 999999, "quantity": 1},
            {"item_id": k, "quantity": 1},
            {"item_id": k, "quantity": 1},
            {"product_id": foreign, "quantity": 1},
            {"product_id": kopi, "quantity": 2.5},
            {"product_id": teh, "quantity": 4},
        ]),
    )
    .await;
    let codes = |v: &[(i64, &str)]| -> Vec<(i64, String)> {
        v.iter().map(|(n, c)| (*n, (*c).to_owned())).collect()
    };
    assert_eq!(
        line_errors(&res),
        codes(&[
            (1, "item_not_found"),
            (3, "item_not_found"),
            (4, "product_not_found"),
            (5, "invalid_quantity"),
            (6, "stock_insufficient"),
        ])
    );
    // Stock counts the restored old sale: Kopi 8 + 2 = 10, so 10 is fine, 11 is not.
    let res = revise(
        &app,
        &t,
        id,
        Uuid::new_v4(),
        json!([{"product_id": kopi, "quantity": 11}]),
    )
    .await;
    assert_eq!(line_errors(&res), codes(&[(1, "stock_insufficient")]));
    let res = revise(
        &app,
        &t,
        id,
        Uuid::new_v4(),
        json!([{"product_id": kopi, "quantity": 10}]),
    )
    .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    assert_eq!(stock(&app, kopi).await, 0);

    // Nothing was changed by the failures.
    let id2 = sell(&app, &t, &[("Teh", 1)]).await;
    for items in [
        json!([]),
        Value::Array(vec![json!({"product_id": teh, "quantity": 1}); 201]),
    ] {
        let res = revise(&app, &t, id2, Uuid::new_v4(), items).await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{}", res.text);
        assert_eq!(res.json["error"]["code"], "invalid_body");
    }
    assert_eq!(detail(&app, &t, id2).await["status"], "completed");
    assert_eq!(stock(&app, teh).await, 2);
}

#[tokio::test]
async fn item_of_a_deleted_product_survives_a_revision() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let kopi = product(&app, &t, "Kopi", 5000, 10).await;
    let teh = product(&app, &t, "Teh", 2000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 2), ("Teh", 1)]).await;
    let res = app
        .delete_json(&format!("/api/v1/products/{teh}"), Some(&t), None)
        .await;
    assert!(res.status.is_success(), "{}", res.text);
    let old = detail(&app, &t, id).await;
    assert_eq!(old["items"][1]["product_id"], Value::Null);

    let res = revise(
        &app,
        &t,
        id,
        Uuid::new_v4(),
        json!([{"item_id": item_id(&old, 1), "quantity": 1}, {"item_id": item_id(&old, 0), "quantity": 1}]),
    )
    .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let items = &res.json["items"];
    assert_eq!(items[0]["product_id"], Value::Null);
    assert_eq!(items[0]["product_name"], "Teh");
    assert_eq!(items[0]["unit_price"], 2000);
    assert_eq!(items[1]["product_id"], kopi);
    assert_eq!(res.json["total"], 7000);
    assert_eq!(stock(&app, kopi).await, 9);
}

#[tokio::test]
async fn revise_needs_create_and_void_and_is_scoped_to_the_user() {
    use backend::auth::perms::Permissions;
    use backend::state::AppState;
    use std::sync::Arc;
    let mut app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let other = app
        .register("Budi", "budi@example.com", "password123")
        .await;
    let kopi = product(&app, &t, "Kopi", 5000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 1)]).await;
    let items = json!([{"product_id": kopi, "quantity": 2}]);

    let res = revise(&app, &t, 999999, Uuid::new_v4(), items.clone()).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND, "{}", res.text);
    let res = revise(&app, &other, id, Uuid::new_v4(), items.clone()).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND, "{}", res.text);
    let res = app
        .post_json(&format!("{URL}/{id}/revise"), None, &json!({}))
        .await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);

    // A role with transaction.create but not transaction.void, and the broadcaster.
    let uid: Uuid = app
        .client()
        .await
        .query_one("SELECT id FROM users WHERE email = 'siti@example.com'", &[])
        .await
        .unwrap()
        .get(0);
    app.client()
        .await
        .batch_execute(
            "INSERT INTO roles (id, name) VALUES (3, 'cashier');
             INSERT INTO role_permission (role_id, permission_id)
               SELECT 3, id FROM permissions WHERE name = 'transaction.create';",
        )
        .await
        .unwrap();
    app.router = backend::routes::router(AppState {
        pool: app.pool.clone(),
        config: app.config.clone(),
        perms: Arc::new(Permissions::load(&app.pool).await.unwrap()),
        google_keys: Arc::default(),
        storage: None,
    });
    for role in [3, 2] {
        let token = backend::auth::jwt::issue_token(
            &app.config.jwt_secret,
            uid,
            role,
            0,
            app.config.jwt_expires_in,
        )
        .unwrap();
        let res = revise(&app, &token, id, Uuid::new_v4(), items.clone()).await;
        assert_eq!(res.status, StatusCode::FORBIDDEN, "{}", res.text);
    }
    assert_eq!(detail(&app, &t, id).await["status"], "completed");
}

#[tokio::test]
async fn analytics_month_counts_only_the_new_version() {
    let app = TestApp::new().await;
    let t = app
        .register("Siti", "siti@example.com", "password123")
        .await;
    let kopi = product(&app, &t, "Kopi", 5000, 10).await;
    let id = sell(&app, &t, &[("Kopi", 2)]).await;
    set_time(&app, id, "2026-03-10 03:00:00+00").await;
    let month = || async {
        app.get("/api/v1/analytics/month?month=2026-03", Some(&t))
            .await
            .json
    };
    assert_eq!(month().await["revenue"], 10000);

    let res = revise(
        &app,
        &t,
        id,
        Uuid::new_v4(),
        json!([{"product_id": kopi, "quantity": 3}]),
    )
    .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let j = month().await;
    assert_eq!(j["revenue"], 15000);
    assert_eq!(j["transaction_count"], 1);
}
