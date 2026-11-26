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
