//! Shared application state, cloned into every handler.

use std::sync::Arc;

use deadpool_postgres::Pool;

use crate::auth::google::GoogleKeys;
use crate::auth::perms::Permissions;
use crate::config::Config;
use crate::storage::Storage;

#[derive(Clone)]
pub struct AppState {
    pub pool: Pool,
    pub config: Arc<Config>,
    /// Role permissions, loaded once at startup (`Permissions::load`).
    pub perms: Arc<Permissions>,
    /// Cached Google signing keys for `POST /auth/google`.
    pub google_keys: Arc<GoogleKeys>,
    /// Photo storage. `None` when Tigris is not configured.
    pub storage: Option<Arc<dyn Storage>>,
}
