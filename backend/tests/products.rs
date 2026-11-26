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

    assert!(!products::delete(&**client, budi, p.id).await.unwrap());
    assert!(products::delete(&**client, siti, p.id).await.unwrap());
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
