mod common;

use backend::db;
use common::TestApp;

/// `TestApp::new` has already applied V1 on an empty database.
#[tokio::test]
async fn migrations_apply_once_and_create_the_schema() {
    let app = TestApp::new().await;

    let again = db::run_migrations(&app.pool).await.expect("second run");
    assert!(again.is_empty(), "second run applies nothing");

    let client = app.client().await;
    let count = |sql: &'static str| {
        let client = &client;
        async move {
            client
                .query_one(sql, &[])
                .await
                .expect(sql)
                .get::<_, i64>(0)
        }
    };

    assert_eq!(
        count("SELECT count(*) FROM refinery_schema_history").await,
        2
    );

    // roles, permissions, role_permission, users, auth_identities, products,
    // transactions, transaction_items, stock_movements, broadcasts
    let tables = count(
        "SELECT count(*) FROM information_schema.tables \
         WHERE table_schema = 'public' AND table_type = 'BASE TABLE' \
         AND table_name <> 'refinery_schema_history'",
    )
    .await;
    assert_eq!(tables, 10);

    let views = count(
        "SELECT count(*) FROM information_schema.views \
         WHERE table_schema = 'public' AND table_name = 'v_daily_sales'",
    )
    .await;
    assert_eq!(views, 1);

    // users_updated_at, users_before_write, products_updated_at,
    // stock_movements_apply, products_initial_stock, items_sale_stock,
    // transactions_void_stock
    let triggers = count("SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal").await;
    assert_eq!(triggers, 7);

    assert_eq!(count("SELECT count(*) FROM roles").await, 2);
    assert_eq!(count("SELECT count(*) FROM permissions").await, 9);
    assert_eq!(count("SELECT count(*) FROM role_permission").await, 10);

    let photo_key = count(
        "SELECT count(*) FROM information_schema.columns \
         WHERE table_name = 'products' AND column_name = 'photo_key'",
    )
    .await;
    assert_eq!(photo_key, 1);
}
