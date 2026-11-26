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
