//! Shared application state, cloned into every handler.

use std::sync::Arc;

use deadpool_postgres::Pool;

use crate::config::Config;

/// Storage, JWT, Google and permission-cache handles are added by later branches.
#[derive(Clone)]
pub struct AppState {
    pub pool: Pool,
    pub config: Arc<Config>,
}
