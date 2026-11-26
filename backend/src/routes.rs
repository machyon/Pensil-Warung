//! HTTP router. Routes and layers are added as features land.

use axum::Router;

use crate::state::AppState;

pub fn router(state: AppState) -> Router {
    Router::new().with_state(state)
}
