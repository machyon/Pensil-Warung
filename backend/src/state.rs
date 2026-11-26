//! Shared application state, cloned into every handler.

use std::sync::Arc;

use deadpool_postgres::Pool;

use crate::auth::perms::Permissions;
use crate::config::Config;

/// Storage and Google handles are added by later branches.
#[derive(Clone)]
pub struct AppState {
    pub pool: Pool,
    pub config: Arc<Config>,
    /// Role permissions, loaded once at startup (`Permissions::load`).
    pub perms: Arc<Permissions>,
}
