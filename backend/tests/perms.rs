mod common;

use backend::auth::perms::{Perm, Permissions};
use common::TestApp;

#[tokio::test]
async fn seeded_permissions_load_for_both_roles() {
    let app = TestApp::new().await;
    let perms = Permissions::load(&app.pool).await.expect("load");
    assert!(perms.has(1, Perm::TransactionCreate));
    assert!(!perms.has(1, Perm::BroadcastCreate));
    assert!(perms.has(2, Perm::BroadcastCreate));
    assert!(!perms.has(2, Perm::ProductManage));
    assert_eq!(perms.names(1).len(), 6);
    assert_eq!(perms.names(2).len(), 4);
}
