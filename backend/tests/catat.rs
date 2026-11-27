mod common;

use std::sync::Arc;

use axum::http::StatusCode;
use axum::response::IntoResponse;
use backend::auth::perms::Permissions;
use backend::catat::dto::Batch;
use backend::catat::exec::execute;
use backend::catat::plan::{Plan, ProductRef, Step};
use backend::state::AppState;
use backend::storage::Storage;
use common::{TestApp, TestResponse};
use http_body_util::BodyExt;
use rust_decimal::Decimal;
use serde_json::{Value, json};
use uuid::Uuid;

const URL: &str = "/api/v1/catat";

async fn product(app: &TestApp, token: &str, name: &str, price: i64, stock: i64) -> i64 {
    let body = json!({"name": name, "price": price, "stock": stock});
    let res = app.post_json("/api/v1/products", Some(token), &body).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    res.json["id"].as_i64().unwrap()
}

async fn catat(app: &TestApp, token: &str, uuid: Uuid, raw: &str, ops: Value) -> TestResponse {
    let body = json!({"client_uuid": uuid, "raw_text": raw, "ops": ops});
    app.post_json(URL, Some(token), &body).await
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

async fn count(app: &TestApp, table: &str) -> i64 {
    app.client()
        .await
        .query_one(&format!("SELECT count(*) FROM {table}"), &[])
        .await
        .unwrap()
        .get(0)
}

/// (reason, delta, stock_after) of a product's movements, oldest first.
async fn movements(app: &TestApp, id: i64) -> Vec<(String, i64, i64)> {
    let rows = app
        .client()
        .await
        .query(
            "SELECT reason::text, delta::bigint, stock_after::bigint FROM stock_movements
             WHERE product_id = $1 ORDER BY id",
            &[&id],
        )
        .await
        .unwrap();
    rows.iter()
        .map(|r| (r.get(0), r.get(1), r.get(2)))
        .collect()
}

fn mv(reason: &str, delta: i64, after: i64) -> (String, i64, i64) {
    (reason.to_owned(), delta, after)
}

fn line_codes(res: &TestResponse) -> Vec<(i64, String)> {
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

async fn user(app: &TestApp) -> String {
    app.register("Siti", "siti@example.com", "rahasia123").await
}

#[tokio::test]
async fn mixed_batch_saves_transaction_items_movements_and_response() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let nasi = product(&app, &t, "Nasi Goreng", 15000, 10).await;
    let teh = product(&app, &t, "Es Teh Manis", 3000, 5).await;
    let kopi = product(&app, &t, "Kopi Susu", 4000, 2).await;
    let raw = "nasi goreng 2\n es teh manis 3 \ntambah stok kopi susu 10\nhapus stok kopi susu 4\nbuat produk roti harga 5000 stok 4\n";
    let ops = json!([
        {"line_no": 1, "op": "sale", "product": "nasi goreng", "quantity": 2},
        {"line_no": 2, "op": "sale", "product": "ES TEH  manis", "quantity": 3},
        {"line_no": 3, "op": "restock", "product": "kopi susu", "quantity": 10},
        {"line_no": 4, "op": "adjust_down", "product": "kopi susu", "quantity": 4},
        {"line_no": 5, "op": "create_product", "name": "Roti", "price": 5000, "stock": 4},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), raw, ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);

    let tx = &res.json["transaction"];
    assert_eq!(tx["raw_text"], raw);
    assert_eq!(tx["total"], 39000);
    assert_eq!(tx["status"], "completed");
    let items = tx["items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0]["line_no"], 1);
    assert_eq!(items[0]["product_id"], nasi);
    assert_eq!(items[0]["product_name"], "Nasi Goreng");
    assert_eq!(items[0]["unit_price"], 15000);
    assert_eq!(items[0]["quantity"], 2);
    assert_eq!(items[0]["line_total"], 30000);
    assert_eq!(items[1]["product_id"], teh);
    assert_eq!(items[1]["line_total"], 9000);

    let changed: Vec<(String, i64)> = res.json["products_changed"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| {
            (
                p["name"].as_str().unwrap().to_owned(),
                p["stock"].as_i64().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        changed,
        [
            ("Nasi Goreng".to_owned(), 8),
            ("Es Teh Manis".to_owned(), 2),
            ("Kopi Susu".to_owned(), 8),
            ("Roti".to_owned(), 4),
        ]
    );
    assert_eq!(res.json["products_deleted"], json!([]));

    assert_eq!(
        movements(&app, nasi).await,
        [mv("initial", 10, 10), mv("sale", -2, 8)]
    );
    assert_eq!(
        movements(&app, teh).await,
        [mv("initial", 5, 5), mv("sale", -3, 2)]
    );
    assert_eq!(
        movements(&app, kopi).await,
        [
            mv("initial", 2, 2),
            mv("restock", 10, 12),
            mv("adjustment", -4, 8)
        ]
    );
    // Only sales have a transaction; restock and adjustment movements do not.
    let linked: i64 = app
        .client()
        .await
        .query_one(
            "SELECT count(*) FROM stock_movements WHERE transaction_item_id IS NOT NULL",
            &[],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(linked, 2);
}

#[tokio::test]
async fn short_lines_are_all_reported_and_nothing_is_saved() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let nasi = product(&app, &t, "Nasi Goreng", 15000, 3).await;
    let teh = product(&app, &t, "Es Teh Manis", 3000, 1).await;
    let ops = json!([
        {"line_no": 1, "op": "sale", "product": "nasi goreng", "quantity": 1},
        {"line_no": 2, "op": "sale", "product": "nasi goreng", "quantity": 5},
        {"line_no": 3, "op": "sale", "product": "es teh manis", "quantity": 2},
        {"line_no": 4, "op": "adjust_down", "product": "es teh manis", "quantity": 9},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "lines_invalid");
    let short = "stock_insufficient".to_owned();
    assert_eq!(
        line_codes(&res),
        [(2, short.clone()), (3, short.clone()), (4, short)]
    );
    assert_eq!(count(&app, "transactions").await, 0);
    assert_eq!(count(&app, "transaction_items").await, 0);
    assert_eq!(stock(&app, nasi).await, 3);
    assert_eq!(stock(&app, teh).await, 1);
    assert_eq!(movements(&app, nasi).await.len(), 1);
}

#[tokio::test]
async fn restock_then_sell_in_the_same_batch() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let kopi = product(&app, &t, "Kopi Susu", 4000, 0).await;
    let ops = json!([
        {"line_no": 1, "op": "restock", "product": "kopi susu", "quantity": 5},
        {"line_no": 2, "op": "sale", "product": "kopi susu", "quantity": 5},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    assert_eq!(res.json["transaction"]["total"], 20000);
    assert_eq!(stock(&app, kopi).await, 0);
    assert_eq!(
        movements(&app, kopi).await,
        [mv("restock", 5, 5), mv("sale", -5, 0)]
    );
}

#[tokio::test]
async fn unknown_product_is_a_line_error_and_rolls_back_the_valid_lines() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let nasi = product(&app, &t, "Nasi Goreng", 15000, 3).await;
    let ops = json!([
        {"line_no": 1, "op": "sale", "product": "nasi goreng", "quantity": 1},
        {"line_no": 2, "op": "sale", "product": "bakso", "quantity": 1},
        {"line_no": 3, "op": "delete_product", "product": "mie ayam"},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    let nf = "product_not_found".to_owned();
    assert_eq!(line_codes(&res), [(2, nf.clone()), (3, nf)]);
    assert_eq!(count(&app, "transactions").await, 0);
    assert_eq!(stock(&app, nasi).await, 3);
}

#[tokio::test]
async fn create_then_sell_uses_the_new_product() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let ops = json!([
        {"line_no": 1, "op": "create_product", "name": "Roti  Bakar", "price": 5000, "stock": 3},
        {"line_no": 2, "op": "sale", "product": "roti bakar", "quantity": 2},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let item = &res.json["transaction"]["items"][0];
    assert_eq!(item["product_name"], "Roti Bakar");
    assert_eq!(item["unit_price"], 5000);
    assert_eq!(res.json["transaction"]["total"], 10000);
    let id = item["product_id"].as_i64().unwrap();
    assert_eq!(res.json["products_changed"][0]["id"], id);
    assert_eq!(res.json["products_changed"][0]["stock"], 1);
    assert_eq!(
        movements(&app, id).await,
        [mv("initial", 3, 3), mv("sale", -2, 1)]
    );
}

#[tokio::test]
async fn delete_removes_the_product_and_its_photo_object() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let id = product(&app, &t, "Nasi Goreng", 15000, 1).await;
    let storage = app.storage.clone().unwrap();
    storage
        .put("products/x/photo.jpg", vec![1], "image/jpeg")
        .await
        .unwrap();
    app.client()
        .await
        .execute(
            "UPDATE products SET photo_key = 'products/x/photo.jpg' WHERE id = $1",
            &[&id],
        )
        .await
        .unwrap();

    let ops = json!([{"line_no": 1, "op": "delete_product", "product": "nasi goreng"}]);
    let res = catat(&app, &t, Uuid::new_v4(), "hapus nasi goreng", ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    assert_eq!(res.json["transaction"], Value::Null);
    assert_eq!(res.json["products_changed"], json!([]));
    assert_eq!(res.json["products_deleted"], json!([id]));
    assert_eq!(count(&app, "products").await, 0);
    assert!(storage.keys().is_empty());
}

#[tokio::test]
async fn sell_then_delete_keeps_the_item_with_a_null_product() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let id = product(&app, &t, "Nasi Goreng", 15000, 5).await;
    let ops = json!([
        {"line_no": 1, "op": "sale", "product": "nasi goreng", "quantity": 2},
        {"line_no": 2, "op": "delete_product", "product": "nasi goreng"},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let item = &res.json["transaction"]["items"][0];
    assert_eq!(item["product_id"], Value::Null);
    assert_eq!(item["product_name"], "Nasi Goreng");
    assert_eq!(item["line_total"], 30000);
    assert_eq!(res.json["products_changed"], json!([]));
    assert_eq!(res.json["products_deleted"], json!([id]));
    assert_eq!(count(&app, "products").await, 0);
    assert_eq!(count(&app, "transaction_items").await, 1);
}

#[tokio::test]
async fn retry_with_the_same_client_uuid_replays_the_transaction() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let nasi = product(&app, &t, "Nasi Goreng", 15000, 5).await;
    let uuid = Uuid::new_v4();
    let ops = json!([{"line_no": 1, "op": "sale", "product": "nasi goreng", "quantity": 2}]);

    let first = catat(&app, &t, uuid, "nasi goreng 2", ops.clone()).await;
    assert_eq!(first.status, StatusCode::CREATED, "{}", first.text);
    // The stock changes between the two calls: the replay shows the current value.
    let restock = json!([{"line_no": 1, "op": "restock", "product": "nasi goreng", "quantity": 4}]);
    catat(&app, &t, Uuid::new_v4(), "x", restock).await;

    let again = catat(&app, &t, uuid, "nasi goreng 2", ops).await;
    assert_eq!(again.status, StatusCode::OK, "{}", again.text);
    assert_eq!(
        again.json["transaction"]["id"],
        first.json["transaction"]["id"]
    );
    assert_eq!(
        again.json["transaction"]["items"],
        first.json["transaction"]["items"]
    );
    assert_eq!(again.json["products_changed"][0]["id"], nasi);
    assert_eq!(again.json["products_changed"][0]["stock"], 7);
    assert_eq!(again.json["products_changed"][0]["price"], 15000);
    assert_eq!(again.json["products_deleted"], json!([]));
    assert_eq!(count(&app, "transactions").await, 1);
    assert_eq!(count(&app, "transaction_items").await, 1);
    assert_eq!(stock(&app, nasi).await, 7);
}

#[tokio::test]
async fn client_price_is_ignored() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    product(&app, &t, "Nasi Goreng", 15000, 5).await;
    let ops = json!([
        {"line_no": 1, "op": "sale", "product": "nasi goreng", "quantity": 1,
         "price": 1, "unit_price": 1, "line_total": 1, "occurred_at": "2020-01-01T00:00:00Z"},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    assert_eq!(res.json["transaction"]["items"][0]["unit_price"], 15000);
    assert_eq!(res.json["transaction"]["total"], 15000);
    assert!(
        res.json["transaction"]["occurred_at"]
            .as_str()
            .unwrap()
            .starts_with(&time::OffsetDateTime::now_utc().year().to_string())
    );
}

#[tokio::test]
async fn another_users_product_is_not_found() {
    let app = TestApp::new().await;
    let a = user(&app).await;
    let b = app.register("Budi", "budi@example.com", "rahasia123").await;
    let id = product(&app, &a, "Nasi Goreng", 15000, 5).await;
    let ops = json!([
        {"line_no": 1, "op": "sale", "product": "nasi goreng", "quantity": 1},
        {"line_no": 2, "op": "restock", "product": "nasi goreng", "quantity": 1},
        {"line_no": 3, "op": "delete_product", "product": "nasi goreng"},
    ]);
    let res = catat(&app, &b, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    let nf = "product_not_found".to_owned();
    assert_eq!(
        line_codes(&res),
        [(1, nf.clone()), (2, nf.clone()), (3, nf)]
    );
    assert_eq!(stock(&app, id).await, 5);
    assert_eq!(count(&app, "products").await, 1);
}

#[tokio::test]
async fn permissions_are_checked_before_any_db_work() {
    let mut app = TestApp::new().await;
    user(&app).await;
    let sale = json!([{"line_no": 1, "op": "sale", "product": "x", "quantity": 1}]);
    let restock = json!([{"line_no": 1, "op": "restock", "product": "x", "quantity": 1}]);

    // No token.
    let res = app
        .post_json(
            URL,
            None,
            &json!({"client_uuid": Uuid::new_v4(), "raw_text": "x", "ops": sale}),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNAUTHORIZED);

    // The seeded roles are `user` (everything) and `broadcaster` (neither
    // permission), so add a role that may sell but not manage products.
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
    let state = AppState {
        pool: app.pool.clone(),
        config: app.config.clone(),
        perms: Arc::new(Permissions::load(&app.pool).await.unwrap()),
        google_keys: Arc::default(),
        storage: None,
    };
    app.router = backend::routes::router(state);
    let cashier = backend::auth::jwt::issue_token(
        &app.config.jwt_secret,
        uid,
        3,
        0,
        app.config.jwt_expires_in,
    )
    .unwrap();

    // A non-sale op is 403 even though the product does not exist.
    let res = catat(&app, &cashier, Uuid::new_v4(), "x", restock).await;
    assert_eq!(res.status, StatusCode::FORBIDDEN, "{}", res.text);
    assert_eq!(res.json["error"]["code"], "forbidden");
    // A sale passes the permission check and reaches the planner.
    let res = catat(&app, &cashier, Uuid::new_v4(), "x", sale).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "lines_invalid");
}

async fn user_id(app: &TestApp, email: &str) -> Uuid {
    app.client()
        .await
        .query_one("SELECT id FROM users WHERE email = $1", &[&email])
        .await
        .unwrap()
        .get(0)
}

fn batch(uuid: Uuid) -> Batch {
    Batch {
        client_uuid: uuid,
        raw_text: "x".to_owned(),
        ops: Vec::new(),
    }
}

fn sale(line_no: u32, product: i64, qty: i64, price: i64) -> Step {
    Step::Sale {
        line_no,
        product: ProductRef::Existing(product),
        quantity: Decimal::from(qty),
        unit_price: price,
        line_total: qty * price,
    }
}

/// Runs a hand-built plan (so the planner's stock check is bypassed) and
/// returns the executor's error as (status, line_no/code pairs).
async fn run_plan(app: &TestApp, user: Uuid, steps: Vec<Step>) -> (StatusCode, Vec<(i64, String)>) {
    let total = steps
        .iter()
        .map(|s| match s {
            Step::Sale { line_total, .. } => *line_total,
            _ => 0,
        })
        .sum();
    let mut client = app.client().await;
    let tx = client.transaction().await.unwrap();
    let err = match execute(&*tx, user, &batch(Uuid::new_v4()), Plan { steps, total }).await {
        Err(e) => e,
        Ok(_) => panic!("the executor accepted an oversell"),
    };
    drop(tx); // rollback
    let res = err.into_response();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(json["error"]["code"], "lines_invalid");
    let lines = json["error"]["details"]["lines"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| {
            (
                l["line_no"].as_i64().unwrap(),
                l["code"].as_str().unwrap().to_owned(),
            )
        })
        .collect();
    (status, lines)
}

#[tokio::test]
async fn executor_maps_a_stock_violation_to_the_failing_line() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let uid = user_id(&app, "siti@example.com").await;
    let nasi = product(&app, &t, "Nasi Goreng", 15000, 3).await;
    let teh = product(&app, &t, "Es Teh Manis", 3000, 2).await;
    let short = "stock_insufficient".to_owned();

    // Line 1 is fine, line 2 oversells through a sale item.
    let steps = vec![sale(1, teh, 1, 3000), sale(2, nasi, 5, 15000)];
    let (status, lines) = run_plan(&app, uid, steps).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(lines, [(2, short.clone())]);

    // Line 2 oversells through an adjustment.
    let steps = vec![
        sale(1, teh, 1, 3000),
        Step::AdjustDown {
            line_no: 2,
            product: ProductRef::Existing(nasi),
            quantity: Decimal::from(4),
            note: None,
        },
    ];
    let (status, lines) = run_plan(&app, uid, steps).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(lines, [(2, short)]);

    // Everything rolled back.
    assert_eq!(stock(&app, nasi).await, 3);
    assert_eq!(stock(&app, teh).await, 2);
    assert_eq!(movements(&app, nasi).await.len(), 1);
    assert_eq!(movements(&app, teh).await.len(), 1);
    assert_eq!(count(&app, "transactions").await, 0);
    assert_eq!(count(&app, "transaction_items").await, 0);
}

#[tokio::test]
async fn executor_reports_a_lost_client_uuid_race_without_side_effects() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let uid = user_id(&app, "siti@example.com").await;
    let nasi = product(&app, &t, "Nasi Goreng", 15000, 5).await;
    let uuid = Uuid::new_v4();
    // The "winner" already stored its transaction; the loser skips the handler's pre-check.
    app.client()
        .await
        .execute(
            "INSERT INTO transactions (user_id, client_uuid, raw_text, total) VALUES ($1, $2, 'w', 0)",
            &[&uid, &uuid],
        )
        .await
        .unwrap();

    let mut client = app.client().await;
    let tx = client.transaction().await.unwrap();
    let plan = Plan {
        steps: vec![sale(1, nasi, 2, 15000)],
        total: 30000,
    };
    let out = execute(&*tx, uid, &batch(uuid), plan).await;
    assert!(matches!(out, Ok(None)), "expected the conflict outcome");
    drop(tx);

    assert_eq!(count(&app, "transactions").await, 1);
    assert_eq!(count(&app, "transaction_items").await, 0);
    assert_eq!(stock(&app, nasi).await, 5);
    assert_eq!(movements(&app, nasi).await.len(), 1);
}

#[tokio::test]
async fn concurrent_duplicates_store_one_transaction() {
    // More connections than requests, so they really overlap.
    let app = TestApp::with_config(|c| c.database_pool_max = 8).await;
    let t = user(&app).await;
    let nasi = product(&app, &t, "Nasi Goreng", 15000, 10).await;
    let uuid = Uuid::new_v4();
    let ops = json!([{"line_no": 1, "op": "sale", "product": "nasi goreng", "quantity": 2}]);

    let results = futures_join(
        (0..5)
            .map(|_| catat(&app, &t, uuid, "nasi goreng 2", ops.clone()))
            .collect(),
    )
    .await;

    let created = results
        .iter()
        .filter(|r| r.status == StatusCode::CREATED)
        .count();
    let replayed = results
        .iter()
        .filter(|r| r.status == StatusCode::OK)
        .count();
    assert_eq!(
        (created, replayed),
        (1, 4),
        "{:?}",
        results.iter().map(|r| &r.text).collect::<Vec<_>>()
    );
    let id = &results[0].json["transaction"]["id"];
    assert!(id.is_i64());
    assert!(results.iter().all(|r| &r.json["transaction"]["id"] == id));
    assert_eq!(count(&app, "transactions").await, 1);
    assert_eq!(count(&app, "transaction_items").await, 1);
    assert_eq!(stock(&app, nasi).await, 8);
    assert_eq!(movements(&app, nasi).await.len(), 2);
}

/// Polls all futures on this task, so they overlap on the shared pool.
async fn futures_join<F: std::future::Future>(fs: Vec<F>) -> Vec<F::Output> {
    let mut set = Vec::new();
    for f in fs {
        set.push(Box::pin(f));
    }
    let mut out: Vec<Option<F::Output>> = set.iter().map(|_| None).collect();
    std::future::poll_fn(|cx| {
        let mut pending = false;
        for (f, o) in set.iter_mut().zip(out.iter_mut()) {
            if o.is_none() {
                match f.as_mut().poll(cx) {
                    std::task::Poll::Ready(v) => *o = Some(v),
                    std::task::Poll::Pending => pending = true,
                }
            }
        }
        if pending {
            std::task::Poll::Pending
        } else {
            std::task::Poll::Ready(())
        }
    })
    .await;
    out.into_iter().map(Option::unwrap).collect()
}

#[tokio::test]
async fn price_change_applies_to_later_sale_lines_only() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let teh = product(&app, &t, "Es Teh Manis", 5000, 10).await;
    let ops = json!([
        {"line_no": 1, "op": "sale", "product": "es teh manis", "quantity": 1},
        {"line_no": 2, "op": "set_price", "product": "es teh manis", "price": 6000},
        {"line_no": 3, "op": "sale", "product": "es teh manis", "quantity": 2},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let items = &res.json["transaction"]["items"];
    assert_eq!(items[0]["unit_price"], 5000);
    assert_eq!(items[1]["unit_price"], 6000);
    assert_eq!(res.json["transaction"]["total"], 17000);
    assert_eq!(res.json["products_changed"][0]["id"], teh);
    assert_eq!(res.json["products_changed"][0]["price"], 6000);
    let price: i64 = app
        .client()
        .await
        .query_one("SELECT price FROM products WHERE id = $1", &[&teh])
        .await
        .unwrap()
        .get(0);
    assert_eq!(price, 6000);
}

#[tokio::test]
async fn set_price_alone_changes_the_product_and_needs_no_transaction() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    product(&app, &t, "Kopi", 3000, 1).await;
    let ops = json!([{"line_no": 1, "op": "set_price", "product": "kopi", "price": 3500}]);
    let res = catat(&app, &t, Uuid::new_v4(), "ubah harga kopi 3500", ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    assert_eq!(res.json["transaction"], Value::Null);
    assert_eq!(res.json["products_changed"][0]["price"], 3500);
}

#[tokio::test]
async fn invalid_price_and_unknown_product_are_line_errors() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let kopi = product(&app, &t, "Kopi", 3000, 1).await;
    let ops = json!([
        {"line_no": 1, "op": "set_price", "product": "kopi", "price": -1},
        {"line_no": 2, "op": "set_price", "product": "kopi", "price": 1.5},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{}", res.text);
    assert_eq!(
        line_codes(&res),
        [(1, "invalid_price".into()), (2, "invalid_price".into())]
    );
    let ops = json!([{"line_no": 1, "op": "set_price", "product": "hantu", "price": 1}]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(line_codes(&res), [(1, "product_not_found".into())]);
    let price: i64 = app
        .client()
        .await
        .query_one("SELECT price FROM products WHERE id = $1", &[&kopi])
        .await
        .unwrap()
        .get(0);
    assert_eq!(price, 3000);
}

async fn movement_notes(app: &TestApp, id: i64) -> Vec<Option<String>> {
    let rows = app
        .client()
        .await
        .query(
            "SELECT note FROM stock_movements WHERE product_id = $1 AND reason = 'adjustment' ORDER BY id",
            &[&id],
        )
        .await
        .unwrap();
    rows.iter().map(|r| r.get(0)).collect()
}

#[tokio::test]
async fn adjust_down_note_is_stored_trimmed_and_blank_is_none() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let kopi = product(&app, &t, "Kopi", 3000, 10).await;
    let ops = json!([
        {"line_no": 1, "op": "adjust_down", "product": "kopi", "quantity": 1, "note": "  basi "},
        {"line_no": 2, "op": "adjust_down", "product": "kopi", "quantity": 1, "note": "   "},
        {"line_no": 3, "op": "adjust_down", "product": "kopi", "quantity": 1},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    assert_eq!(
        movement_notes(&app, kopi).await,
        [Some("basi".to_owned()), None, None]
    );
    assert_eq!(stock(&app, kopi).await, 7);
}

#[tokio::test]
async fn adjust_down_note_over_200_chars_is_invalid_value() {
    let app = TestApp::new().await;
    let t = user(&app).await;
    let kopi = product(&app, &t, "Kopi", 3000, 10).await;
    let ops = json!([
        {"line_no": 1, "op": "adjust_down", "product": "kopi", "quantity": 1, "note": "x".repeat(201)},
    ]);
    let res = catat(&app, &t, Uuid::new_v4(), "x", ops).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{}", res.text);
    assert_eq!(line_codes(&res), [(1, "invalid_value".into())]);
    assert_eq!(stock(&app, kopi).await, 10);
}
