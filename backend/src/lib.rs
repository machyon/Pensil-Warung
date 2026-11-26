//! Pensil Warung API as a library, so the binary in `main.rs` and the
//! integration tests in `tests/` share the same modules.

pub mod account;
pub mod auth;
pub mod common;
pub mod config;
pub mod db;
pub mod error;
pub mod products;
pub mod routes;
pub mod state;
