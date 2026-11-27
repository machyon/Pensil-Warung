mod common;

use backend::products::{self, NewProduct};
use common::TestApp;
use rust_decimal::Decimal;
use uuid::Uuid;

async fn user_id(app: &TestApp, email: &str) -> Uuid {
    app.client()
        .await
        .query_one("SELECT id FROM users WHERE email = $1", &[&email])
        .await
        .unwrap()
        .get(0)
}

async fn movements(app: &TestApp, product_id: i64) -> Vec<(String, Decimal, Decimal)> {
    app.client()
        .await
        .query(
            "SELECT reason::text, delta, stock_after FROM stock_movements
             WHERE product_id = $1 ORDER BY id",
            &[&product_id],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| (r.get(0), r.get(1), r.get(2)))
        .collect()
}

#[tokio::test]
async fn zero_stock_creates_no_movement_and_positive_stock_creates_initial() {
    let app = TestApp::new().await;
    app.register("Siti", "siti@example.com", "rahasia123").await;
    let uid = user_id(&app, "siti@example.com").await;
    let client = app.client().await;

    let empty = products::create(&**client, uid, &NewProduct::new("Teh", 3000, 0).unwrap())
        .await
        .unwrap();
    assert!(movements(&app, empty.id).await.is_empty());

    let five = products::create(&**client, uid, &NewProduct::new("Kopi", 4000, 5).unwrap())
        .await
        .unwrap();
    assert_eq!(five.stock, Decimal::from(5));
    assert_eq!(
        movements(&app, five.id).await,
        vec![("initial".to_owned(), Decimal::from(5), Decimal::from(5))]
    );
}

#[tokio::test]
async fn move_stock_find_by_name_and_delete() {
    let app = TestApp::new().await;
    app.register("Siti", "siti@example.com", "rahasia123").await;
    app.register("Budi", "budi@example.com", "rahasia123").await;
    let (siti, budi) = (
        user_id(&app, "siti@example.com").await,
        user_id(&app, "budi@example.com").await,
    );
    let client = app.client().await;
    let p = products::create(
        &**client,
        siti,
        &NewProduct::new("Nasi Goreng", 15000, 2).unwrap(),
    )
    .await
    .unwrap();

    let after = products::move_stock(&**client, p.id, Decimal::from(3), "restock", Some("pasar"))
        .await
        .unwrap();
    assert_eq!(after, Decimal::from(5));
    let err = products::move_stock(&**client, p.id, Decimal::from(-9), "adjustment", None)
        .await
        .unwrap_err();
    assert_eq!(err.code(), backend::error::ErrorCode::StockInsufficient);

    let found = products::find_by_name(&**client, siti, "  NASI   goreng ")
        .await
        .unwrap();
    assert_eq!(found.map(|f| f.id), Some(p.id));
    assert!(
        products::find_by_name(&**client, budi, "nasi goreng")
            .await
            .unwrap()
            .is_none()
    );

    assert!(
        products::delete(&**client, budi, p.id)
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        products::delete(&**client, siti, p.id)
            .await
            .unwrap()
            .is_some()
    );
    assert!(movements(&app, p.id).await.is_empty());
}

#[tokio::test]
async fn duplicate_name_is_name_taken_ignoring_case_and_spaces() {
    let app = TestApp::new().await;
    app.register("Siti", "siti@example.com", "rahasia123").await;
    let uid = user_id(&app, "siti@example.com").await;
    let client = app.client().await;
    products::create(
        &**client,
        uid,
        &NewProduct::new("Nasi Goreng", 1, 0).unwrap(),
    )
    .await
    .unwrap();
    let err = products::create(
        &**client,
        uid,
        &NewProduct::new(" nasi   GORENG", 1, 0).unwrap(),
    )
    .await
    .err()
    .unwrap();
    assert_eq!(err.code(), backend::error::ErrorCode::NameTaken);
}

use axum::http::StatusCode;
use backend::auth::jwt::issue_token;
use serde_json::{Value, json};

const P: &str = "/api/v1/products";

async fn seed(app: &TestApp, token: &str, name: &str, stock: i64) -> Value {
    let uid = {
        let res = app.get("/api/v1/me", Some(token)).await;
        res.json["id"].as_str().unwrap().parse::<Uuid>().unwrap()
    };
    let client = app.client().await;
    let p = products::create(&**client, uid, &NewProduct::new(name, 1000, stock).unwrap())
        .await
        .unwrap();
    json!(p.id)
}

#[tokio::test]
async fn list_and_get_are_scoped_to_the_caller() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let b = app.register("Budi", "budi@example.com", "rahasia123").await;
    let id = seed(&app, &a, "Nasi Goreng", 10).await;

    let res = app.get(&format!("{P}/{id}"), Some(&a)).await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.json["stock"], json!(10));
    assert_eq!(res.json["photo_url"], Value::Null);
    assert!(res.json["created_at"].as_str().unwrap().contains('T'));

    let res = app.get(&format!("{P}/{id}"), Some(&b)).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    assert_eq!(res.json["error"]["code"], "not_found");
    let res = app.get(P, Some(&b)).await;
    assert_eq!(res.json, json!({"items": [], "count": 0}));
    assert_eq!(app.get(P, None).await.status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn list_is_ordered_and_search_escapes_wildcards() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    for name in [
        "Teh Manis",
        "es teh",
        "Gula 100%",
        "Kopi_Hitam",
        "Susu Kopi",
    ] {
        seed(&app, &a, name, 0).await;
    }
    let names = |res: &common::TestResponse| -> Vec<String> {
        res.json["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["name"].as_str().unwrap().to_owned())
            .collect()
    };
    let all = app.get(P, Some(&a)).await;
    assert_eq!(all.json["count"], 5);
    assert_eq!(
        names(&all),
        [
            "es teh",
            "Gula 100%",
            "Kopi_Hitam",
            "Susu Kopi",
            "Teh Manis"
        ]
    );
    assert_eq!(
        names(&app.get(&format!("{P}?q=TEH"), Some(&a)).await),
        ["es teh", "Teh Manis"]
    );
    assert_eq!(
        names(&app.get(&format!("{P}?q=%25"), Some(&a)).await),
        ["Gula 100%"]
    );
    assert_eq!(
        names(&app.get(&format!("{P}?q=_"), Some(&a)).await),
        ["Kopi_Hitam"]
    );
    assert_eq!(
        names(&app.get(&format!("{P}?q=%5C"), Some(&a)).await).len(),
        0
    );
}

#[tokio::test]
async fn role_without_product_manage_is_forbidden() {
    let app = TestApp::new().await;
    app.register("Siti", "siti@example.com", "rahasia123").await;
    let uid = user_id(&app, "siti@example.com").await;
    app.client()
        .await
        .execute("UPDATE users SET role_id = 2 WHERE id = $1", &[&uid])
        .await
        .unwrap();
    let token = issue_token(common::TEST_JWT_SECRET, uid, 2, 0, time::Duration::days(1)).unwrap();
    assert_eq!(app.get(P, Some(&token)).await.status, StatusCode::FORBIDDEN);
    assert_eq!(
        app.get(&format!("{P}/1"), Some(&token)).await.status,
        StatusCode::FORBIDDEN
    );
}

fn item(name: &str, price: i64, stock: i64) -> Value {
    json!({"name": name, "price": price, "stock": stock})
}

async fn count(app: &TestApp) -> i64 {
    app.client()
        .await
        .query_one("SELECT count(*) FROM products", &[])
        .await
        .unwrap()
        .get(0)
}

#[tokio::test]
async fn post_creates_with_integer_stock_and_initial_movement() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let res = app
        .post_json(P, Some(&a), &item("  Nasi   Goreng ", 15000, 5))
        .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    assert_eq!(res.json["name"], "Nasi Goreng");
    assert_eq!(res.json["stock"], json!(5));
    assert!(res.json["stock"].is_i64());
    let id = res.json["id"].as_i64().unwrap();
    assert_eq!(
        movements(&app, id).await,
        vec![("initial".to_owned(), Decimal::from(5), Decimal::from(5))]
    );

    let zero = app.post_json(P, Some(&a), &item("Teh", 3000, 0)).await;
    assert_eq!(zero.json["stock"], json!(0));
    assert!(
        movements(&app, zero.json["id"].as_i64().unwrap())
            .await
            .is_empty()
    );
}

#[tokio::test]
async fn post_validates_and_rejects_duplicates() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let b = app.register("Budi", "budi@example.com", "rahasia123").await;
    app.post_json(P, Some(&a), &item("Nasi Goreng", 1, 1)).await;

    let dup = app
        .post_json(P, Some(&a), &item(" NASI  goreng", 1, 1))
        .await;
    assert_eq!(dup.status, StatusCode::CONFLICT);
    assert_eq!(dup.json["error"]["code"], "name_taken");
    // Another user may reuse the name.
    let other = app.post_json(P, Some(&b), &item("Nasi Goreng", 1, 1)).await;
    assert_eq!(other.status, StatusCode::CREATED);

    for body in [
        item("   ", 1, 1),
        item(&"a".repeat(61), 1, 1),
        item("x", -1, 1),
        item("x", 1, -1),
    ] {
        let res = app.post_json(P, Some(&a), &body).await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    }
    // A fractional stock is not an integer.
    let res = app
        .post_json(P, Some(&a), &json!({"name": "x", "price": 1, "stock": 1.5}))
        .await;
    assert!(res.status.is_client_error());
    assert_eq!(res.json["error"]["code"], "invalid_body");
    assert_eq!(count(&app).await, 2);
}

#[tokio::test]
async fn bulk_creates_all_items() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let res = app
        .post_json(
            &format!("{P}/bulk"),
            Some(&a),
            &json!({"items": [item("Teh", 3000, 0), item("Kopi", 4000, 7)]}),
        )
        .await;
    assert_eq!(res.status, StatusCode::CREATED, "{}", res.text);
    let items = res.json["items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[1]["stock"], json!(7));
    assert_eq!(count(&app).await, 2);

    for body in [
        json!({"items": []}),
        json!({"items": vec![item("x", 1, 1); 51]}),
    ] {
        let res = app.post_json(&format!("{P}/bulk"), Some(&a), &body).await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    }
}

#[tokio::test]
async fn bulk_is_atomic_and_reports_the_duplicate_index() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    app.post_json(P, Some(&a), &item("Kopi", 1, 1)).await;
    let bulk = format!("{P}/bulk");

    // Duplicate inside the batch: the later item's index.
    let res = app
        .post_json(
            &bulk,
            Some(&a),
            &json!({"items": [item("Teh", 1, 1), item("Gula", 1, 1), item(" TEH ", 1, 1)]}),
        )
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    assert_eq!(res.json["error"]["code"], "name_taken");
    assert_eq!(res.json["error"]["details"]["index"], 2);

    // Clash with an existing product: that item's index, and nothing is kept.
    let res = app
        .post_json(
            &bulk,
            Some(&a),
            &json!({"items": [item("Teh", 1, 1), item("kopi", 1, 1), item("Gula", 1, 1)]}),
        )
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    assert_eq!(res.json["error"]["details"]["index"], 1);

    // An invalid item also leaves nothing behind.
    let res = app
        .post_json(
            &bulk,
            Some(&a),
            &json!({"items": [item("Teh", 1, 1), item("Bad", -5, 1)]}),
        )
        .await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(count(&app).await, 1);
}

async fn note_of(app: &TestApp, product_id: i64) -> Vec<Option<String>> {
    app.client()
        .await
        .query(
            "SELECT note FROM stock_movements WHERE product_id = $1 ORDER BY id",
            &[&product_id],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| r.get(0))
        .collect()
}

#[tokio::test]
async fn patch_stock_writes_one_ledger_movement_per_change() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let id = seed(&app, &a, "Nasi Goreng", 10).await;
    let path = format!("{P}/{id}");
    let pid = id.as_i64().unwrap();

    let res = app
        .patch_json(&path, Some(&a), &json!({"stock": 15, "note": "belanja"}))
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["stock"], json!(15));

    let res = app
        .patch_json(&path, Some(&a), &json!({"stock": 12, "note": "rusak"}))
        .await;
    assert_eq!(res.json["stock"], json!(12));

    // Same stock: no movement, and the note is dropped.
    let res = app
        .patch_json(&path, Some(&a), &json!({"stock": 12, "note": "abaikan"}))
        .await;
    assert_eq!(res.status, StatusCode::OK);

    let d = Decimal::from;
    assert_eq!(
        movements(&app, pid).await,
        vec![
            ("initial".to_owned(), d(10), d(10)),
            ("restock".to_owned(), d(5), d(15)),
            ("adjustment".to_owned(), d(-3), d(12)),
        ]
    );
    assert_eq!(
        note_of(&app, pid).await,
        vec![None, Some("belanja".to_owned()), Some("rusak".to_owned())]
    );

    // Stock down to zero is allowed.
    let res = app.patch_json(&path, Some(&a), &json!({"stock": 0})).await;
    assert_eq!(res.json["stock"], json!(0));
}

#[tokio::test]
async fn patch_name_and_price_without_stock_writes_no_movement() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let id = seed(&app, &a, "Nasi Goreng", 4).await;
    let path = format!("{P}/{id}");

    // Re-casing its own name is not a clash.
    let res = app
        .patch_json(
            &path,
            Some(&a),
            &json!({"name": "  NASI  goreng ", "price": 20000}),
        )
        .await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["name"], "NASI goreng");
    assert_eq!(res.json["price"], 20000);
    assert_eq!(res.json["stock"], json!(4));
    assert_eq!(movements(&app, id.as_i64().unwrap()).await.len(), 1);
}

#[tokio::test]
async fn patch_validation_and_conflicts() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    seed(&app, &a, "Teh", 0).await;
    let id = seed(&app, &a, "Kopi", 3).await;
    let path = format!("{P}/{id}");

    let res = app.patch_json(&path, Some(&a), &json!({})).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "nothing_to_update");

    let res = app.patch_json(&path, Some(&a), &json!({"note": "x"})).await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["code"], "invalid_value");
    assert_eq!(res.json["error"]["details"]["field"], "note");

    for body in [
        json!({"stock": -1}),
        json!({"price": -1}),
        json!({"name": "  "}),
        json!({"stock": 1, "note": "a".repeat(201)}),
    ] {
        let res = app.patch_json(&path, Some(&a), &body).await;
        assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    }

    let res = app
        .patch_json(&path, Some(&a), &json!({"name": "teh"}))
        .await;
    assert_eq!(res.status, StatusCode::CONFLICT);
    assert_eq!(res.json["error"]["code"], "name_taken");

    // Nothing above changed the product.
    let res = app.get(&path, Some(&a)).await;
    assert_eq!(res.json["name"], "Kopi");
    assert_eq!(res.json["stock"], json!(3));
    assert_eq!(movements(&app, id.as_i64().unwrap()).await.len(), 1);
}

#[tokio::test]
async fn patch_and_delete_of_another_users_product_are_404() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let b = app.register("Budi", "budi@example.com", "rahasia123").await;
    let id = seed(&app, &a, "Nasi Goreng", 10).await;
    let path = format!("{P}/{id}");

    let res = app.patch_json(&path, Some(&b), &json!({"stock": 1})).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    let res = app.delete_json(&path, Some(&b), None).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    let res = app
        .delete_json(&format!("{P}/999999"), Some(&a), None)
        .await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);

    let res = app.get(&path, Some(&a)).await;
    assert_eq!(res.json["stock"], json!(10));
}

#[tokio::test]
async fn delete_removes_movements_but_keeps_sale_snapshots() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let uid = user_id(&app, "siti@example.com").await;
    let id = seed(&app, &a, "Nasi Goreng", 10).await;
    let pid = id.as_i64().unwrap();
    let client = app.client().await;

    // The items_sale_stock trigger also writes a 'sale' movement.
    let tx_id: i64 = client
        .query_one(
            "INSERT INTO transactions (user_id, raw_text, total) VALUES ($1, 'nasi goreng 2', 2000)
             RETURNING id",
            &[&uid],
        )
        .await
        .unwrap()
        .get(0);
    client
        .execute(
            "INSERT INTO transaction_items
               (transaction_id, product_id, line_no, product_name, unit_price, quantity, line_total)
             VALUES ($1, $2, 1, 'Nasi Goreng', 1000, 2, 2000)",
            &[&tx_id, &pid],
        )
        .await
        .unwrap();
    assert_eq!(movements(&app, pid).await.len(), 2);

    let res = app.delete_json(&format!("{P}/{id}"), Some(&a), None).await;
    assert_eq!(res.status, StatusCode::NO_CONTENT);
    assert_eq!(
        app.get(&format!("{P}/{id}"), Some(&a)).await.status,
        StatusCode::NOT_FOUND
    );
    assert!(movements(&app, pid).await.is_empty());

    let row = client
        .query_one(
            "SELECT product_id, product_name, unit_price FROM transaction_items
             WHERE transaction_id = $1",
            &[&tx_id],
        )
        .await
        .unwrap();
    assert_eq!(row.get::<_, Option<i64>>(0), None);
    assert_eq!(row.get::<_, String>(1), "Nasi Goreng");
    assert_eq!(row.get::<_, i64>(2), 1000);
}

fn multipart(field: &str, content_type: &str, bytes: &[u8]) -> (String, Vec<u8>) {
    let boundary = "XBOUNDARYX";
    let mut body = format!(
        "--{boundary}\r\nContent-Disposition: form-data; name=\"{field}\"; filename=\"f\"\r\n\
         Content-Type: {content_type}\r\n\r\n"
    )
    .into_bytes();
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    (format!("multipart/form-data; boundary={boundary}"), body)
}

async fn put_photo(
    app: &TestApp,
    token: &str,
    id: &Value,
    field: &str,
    content_type: &str,
    bytes: &[u8],
) -> common::TestResponse {
    let (ct, body) = multipart(field, content_type, bytes);
    let req = axum::http::Request::put(format!("{P}/{id}/photo"))
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", ct)
        .body(axum::body::Body::from(body))
        .unwrap();
    app.send(req).await
}

fn tiny_png() -> Vec<u8> {
    let mut out = std::io::Cursor::new(Vec::new());
    image::RgbaImage::from_pixel(8, 8, image::Rgba([200, 30, 30, 255]))
        .write_to(&mut out, image::ImageFormat::Png)
        .unwrap();
    out.into_inner()
}

async fn photo_key_of(app: &TestApp, id: &Value) -> Option<String> {
    let id = id.as_i64().unwrap();
    app.client()
        .await
        .query_one("SELECT photo_key FROM products WHERE id = $1", &[&id])
        .await
        .unwrap()
        .get(0)
}

#[tokio::test]
async fn put_photo_stores_a_jpeg_and_replace_deletes_the_old_object() {
    let app = TestApp::new().await;
    let token = app.register("Siti", "siti@example.com", "rahasia123").await;
    let uid = user_id(&app, "siti@example.com").await;
    let id = seed(&app, &token, "Nasi Goreng", 1).await;
    let storage = app.storage.clone().unwrap();
    let prefix = format!("products/{uid}/{id}/");

    // The client's content type is ignored: the bytes decide.
    let res = put_photo(&app, &token, &id, "photo", "text/plain", &tiny_png()).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    assert_eq!(res.json["id"], id);
    let first = photo_key_of(&app, &id).await.unwrap();
    assert!(
        first.starts_with(&prefix) && first.ends_with(".jpg"),
        "{first}"
    );
    assert_eq!(storage.keys(), std::slice::from_ref(&first));
    let (bytes, content_type) = storage.get(&first).unwrap();
    assert_eq!(content_type, "image/jpeg");
    assert_eq!(&bytes[..2], [0xFF, 0xD8]);

    let res = put_photo(&app, &token, &id, "photo", "image/png", &tiny_png()).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    let second = photo_key_of(&app, &id).await.unwrap();
    assert_ne!(first, second);
    assert_eq!(storage.keys(), [second]);
}

#[tokio::test]
async fn put_photo_rejects_bad_input_and_other_users() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let b = app.register("Budi", "budi@example.com", "rahasia123").await;
    let id = seed(&app, &a, "Nasi Goreng", 1).await;

    let res = put_photo(&app, &a, &id, "photo", "image/png", b"not an image").await;
    assert_eq!(res.status, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    assert_eq!(res.json["error"]["code"], "unsupported_image");
    let res = put_photo(&app, &a, &id, "other", "image/png", &tiny_png()).await;
    assert_eq!(res.status, StatusCode::BAD_REQUEST);
    let res = put_photo(&app, &b, &id, "photo", "image/png", &tiny_png()).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    let big = vec![0u8; 5 * 1024 * 1024 + 1];
    let res = put_photo(&app, &a, &id, "photo", "image/png", &big).await;
    assert_eq!(res.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(res.json["error"]["code"], "payload_too_large");

    assert!(app.storage.as_ref().unwrap().keys().is_empty());
    assert_eq!(photo_key_of(&app, &id).await, None);
}

#[tokio::test]
async fn put_photo_without_storage_is_503() {
    let app = TestApp::without_storage().await;
    let token = app.register("Siti", "siti@example.com", "rahasia123").await;
    let id = seed(&app, &token, "Nasi Goreng", 1).await;
    let res = put_photo(&app, &token, &id, "photo", "image/png", &tiny_png()).await;
    assert_eq!(res.status, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(res.json["error"]["code"], "storage_unavailable");
    assert_eq!(photo_key_of(&app, &id).await, None);
}

async fn delete_photo(app: &TestApp, token: &str, id: &Value) -> common::TestResponse {
    app.delete_json(&format!("{P}/{id}/photo"), Some(token), None)
        .await
}

#[tokio::test]
async fn photo_size_limit_applies_to_the_photo_bytes() {
    let app = TestApp::new().await;
    let token = app.register("Siti", "siti@example.com", "rahasia123").await;
    let id = seed(&app, &token, "Nasi Goreng", 1).await;
    let limit = 5 * 1024 * 1024;
    let payload = |len: usize| {
        let mut bytes = vec![7u8; len];
        bytes[..8].copy_from_slice(b"\x89PNG\r\n\x1a\n");
        bytes
    };

    // Past the size check, then rejected by the decoder: 415, not 413.
    let res = put_photo(
        &app,
        &token,
        &id,
        "photo",
        "image/png",
        &payload(limit - 1000),
    )
    .await;
    assert_eq!(res.status, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    let res = put_photo(&app, &token, &id, "photo", "image/png", &payload(limit)).await;
    assert_eq!(res.status, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    let res = put_photo(&app, &token, &id, "photo", "image/png", &payload(limit + 1)).await;
    assert_eq!(res.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(res.json["error"]["code"], "payload_too_large");
}

#[tokio::test]
async fn delete_photo_removes_the_object_and_is_idempotent() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let b = app.register("Budi", "budi@example.com", "rahasia123").await;
    let id = seed(&app, &a, "Nasi Goreng", 1).await;
    let storage = app.storage.clone().unwrap();

    // No photo yet: still 204.
    assert_eq!(
        delete_photo(&app, &a, &id).await.status,
        StatusCode::NO_CONTENT
    );

    put_photo(&app, &a, &id, "photo", "image/png", &tiny_png()).await;
    assert_eq!(storage.keys().len(), 1);
    let res = delete_photo(&app, &b, &id).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    assert_eq!(storage.keys().len(), 1);

    let res = delete_photo(&app, &a, &id).await;
    assert_eq!(res.status, StatusCode::NO_CONTENT);
    assert_eq!(photo_key_of(&app, &id).await, None);
    assert!(storage.keys().is_empty());
    assert_eq!(
        delete_photo(&app, &a, &id).await.status,
        StatusCode::NO_CONTENT
    );
    let res = app.get(&format!("{P}/{id}"), Some(&a)).await;
    assert_eq!(res.json["photo_url"], Value::Null);
}

#[tokio::test]
async fn delete_photo_without_storage_is_503() {
    let app = TestApp::without_storage().await;
    let token = app.register("Siti", "siti@example.com", "rahasia123").await;
    let id = seed(&app, &token, "Nasi Goreng", 1).await;
    let res = delete_photo(&app, &token, &id).await;
    assert_eq!(res.status, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(res.json["error"]["code"], "storage_unavailable");
}

#[tokio::test]
async fn deleting_a_product_removes_its_photo_object() {
    let app = TestApp::new().await;
    let token = app.register("Siti", "siti@example.com", "rahasia123").await;
    let with = seed(&app, &token, "Nasi Goreng", 1).await;
    let without = seed(&app, &token, "Teh", 1).await;
    put_photo(&app, &token, &with, "photo", "image/png", &tiny_png()).await;
    assert_eq!(app.storage.as_ref().unwrap().keys().len(), 1);

    let res = app
        .delete_json(&format!("{P}/{with}"), Some(&token), None)
        .await;
    assert_eq!(res.status, StatusCode::NO_CONTENT);
    assert!(app.storage.as_ref().unwrap().keys().is_empty());
    let res = app
        .delete_json(&format!("{P}/{without}"), Some(&token), None)
        .await;
    assert_eq!(res.status, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn photo_url_is_presigned_only_for_products_with_a_photo() {
    let app = TestApp::new().await;
    let token = app.register("Siti", "siti@example.com", "rahasia123").await;
    let with = seed(&app, &token, "Nasi Goreng", 1).await;
    let without = seed(&app, &token, "Teh", 1).await;

    let put = put_photo(&app, &token, &with, "photo", "image/png", &tiny_png()).await;
    let key = photo_key_of(&app, &with).await.unwrap();
    let expected = json!(format!("https://storage.test/{key}?ttl=3600"));
    assert_eq!(put.json["photo_url"], expected);
    let res = app.get(&format!("{P}/{with}"), Some(&token)).await;
    assert_eq!(res.json["photo_url"], expected);
    let res = app.get(&format!("{P}/{without}"), Some(&token)).await;
    assert_eq!(res.json["photo_url"], Value::Null);

    let res = app.get(P, Some(&token)).await;
    let urls: Vec<&Value> = res.json["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| &p["photo_url"])
        .collect();
    assert_eq!(urls, [&expected, &Value::Null]); // Nasi Goreng, Teh

    let res = app
        .patch_json(
            &format!("{P}/{with}"),
            Some(&token),
            &json!({"price": 2000}),
        )
        .await;
    assert_eq!(res.json["photo_url"], expected);
}

#[tokio::test]
async fn photo_url_is_null_without_storage() {
    let app = TestApp::without_storage().await;
    let token = app.register("Siti", "siti@example.com", "rahasia123").await;
    let id = seed(&app, &token, "Nasi Goreng", 1).await;
    app.client()
        .await
        .execute(
            "UPDATE products SET photo_key = 'products/x/y.jpg' WHERE id = $1",
            &[&id.as_i64().unwrap()],
        )
        .await
        .unwrap();
    let res = app.get(&format!("{P}/{id}"), Some(&token)).await;
    assert_eq!(res.json["photo_url"], Value::Null);
    let res = app.get(P, Some(&token)).await;
    assert_eq!(res.json["items"][0]["photo_url"], Value::Null);
}

#[tokio::test]
async fn movements_are_newest_first_paged_and_sale_has_transaction_id() {
    let app = TestApp::new().await;
    let a = app.register("Siti", "siti@example.com", "rahasia123").await;
    let b = app.register("Budi", "budi@example.com", "rahasia123").await;
    let uid = user_id(&app, "siti@example.com").await;
    let id = seed(&app, &a, "Nasi Goreng", 10).await;
    let pid = id.as_i64().unwrap();
    let path = format!("{P}/{id}");

    app.patch_json(&path, Some(&a), &json!({"stock": 15, "note": "belanja"}))
        .await;
    let client = app.client().await;
    let tx_id: i64 = client
        .query_one(
            "INSERT INTO transactions (user_id, raw_text, total) VALUES ($1, 'nasi goreng 2', 2000)
             RETURNING id",
            &[&uid],
        )
        .await
        .unwrap()
        .get(0);
    client
        .execute(
            "INSERT INTO transaction_items
               (transaction_id, product_id, line_no, product_name, unit_price, quantity, line_total)
             VALUES ($1, $2, 1, 'Nasi Goreng', 1000, 2, 2000)",
            &[&tx_id, &pid],
        )
        .await
        .unwrap();

    let res = app.get(&format!("{path}/movements"), Some(&a)).await;
    assert_eq!(res.status, StatusCode::OK, "{}", res.text);
    let items = res.json["items"].as_array().unwrap();
    let reasons: Vec<_> = items
        .iter()
        .map(|m| m["reason"].as_str().unwrap())
        .collect();
    assert_eq!(reasons, ["sale", "restock", "initial"]);
    assert_eq!(items[0]["delta"], json!(-2));
    assert_eq!(items[0]["stock_after"], json!(13));
    assert_eq!(items[0]["transaction_id"], json!(tx_id));
    assert_eq!(items[1]["note"], "belanja");
    assert_eq!(items[1]["transaction_id"], Value::Null);
    assert_eq!(res.json["next_cursor"], Value::Null);

    // Page by one: every row exactly once, same order.
    let mut seen = vec![];
    let mut url = format!("{path}/movements?limit=1");
    loop {
        let res = app.get(&url, Some(&a)).await;
        seen.push(res.json["items"][0]["reason"].as_str().unwrap().to_string());
        match res.json["next_cursor"].as_str() {
            Some(c) => url = format!("{path}/movements?limit=1&cursor={c}"),
            None => break,
        }
    }
    assert_eq!(seen, reasons);

    let res = app
        .get(&format!("{path}/movements?cursor=garbage"), Some(&a))
        .await;
    assert_eq!(res.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(res.json["error"]["details"]["field"], "cursor");

    let res = app.get(&format!("{path}/movements"), Some(&b)).await;
    assert_eq!(res.status, StatusCode::NOT_FOUND);
    assert_eq!(res.json["error"]["code"], "not_found");
    assert_eq!(
        app.get(&format!("{path}/movements"), None).await.status,
        StatusCode::UNAUTHORIZED
    );
}
