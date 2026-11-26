//! PostgreSQL connection pool and migration runner.
//!
//! Remote hosts always use TLS, verified against `DATABASE_CA_CERT` or
//! `DATABASE_CA_CERT_FILE` when set, else the bundled webpki roots. Plain TCP
//! is used only for localhost, 127.0.0.1 and ::1, and for Unix sockets.

use std::path::PathBuf;
use std::str::FromStr;
use std::sync::Arc;

use deadpool_postgres::{Manager, ManagerConfig, Pool, PoolError, RecyclingMethod, Runtime};
use rustls::{ClientConfig, RootCertStore};
use thiserror::Error;
use tokio_postgres::NoTls;
use tokio_postgres::config::{Host, SslMode};
use tokio_postgres_rustls::MakeRustlsConnect;

use crate::config::Config;

refinery::embed_migrations!("migrations");

#[derive(Debug, Error)]
pub enum DbError {
    #[error("DATABASE_URL is not a valid PostgreSQL connection string: {0}")]
    InvalidUrl(tokio_postgres::Error),
    #[error("could not read CA certificate file {path}: {source}")]
    CaFileRead {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("CA certificate is not valid PEM or contains no certificate")]
    CaPem,
    #[error("CA certificate rejected: {0}")]
    CaCert(rustls::Error),
    #[error("could not build the connection pool: {0}")]
    PoolBuild(#[from] deadpool_postgres::BuildError),
}

#[derive(Debug, Error)]
pub enum MigrateError {
    #[error("could not get a database connection: {0}")]
    Connect(#[from] PoolError),
    #[error("migration failed: {0}")]
    Migration(#[from] refinery::Error),
}

/// Applies every embedded migration in `migrations/` that is not yet recorded in
/// `refinery_schema_history`. Each migration runs in its own transaction.
/// Returns the migrations applied by this call (empty when already up to date).
pub async fn run_migrations(pool: &Pool) -> Result<Vec<refinery::Migration>, MigrateError> {
    let mut client = pool.get().await?;
    // Object -> ClientWrapper -> tokio_postgres::Client, which implements AsyncMigrate.
    let report = migrations::runner().run_async(&mut **client).await?;
    Ok(report.applied_migrations().clone())
}

/// Builds the pool from the config. It does not connect until the first `get()`.
pub fn create_pool(config: &Config) -> Result<Pool, DbError> {
    let mut pg_config =
        tokio_postgres::Config::from_str(&config.database_url).map_err(DbError::InvalidUrl)?;
    let manager_config = ManagerConfig {
        recycling_method: RecyclingMethod::Fast,
    };

    let pool = if is_local(pg_config.get_hosts()) {
        let manager = Manager::from_config(pg_config, NoTls, manager_config);
        Pool::builder(manager)
    } else {
        // Never fall back to plaintext for a remote host.
        pg_config.ssl_mode(SslMode::Require);
        let tls = MakeRustlsConnect::new(tls_client_config(config)?);
        let manager = Manager::from_config(pg_config, tls, manager_config);
        Pool::builder(manager)
    };

    Ok(pool
        .max_size(config.database_pool_max)
        .runtime(Runtime::Tokio1)
        .build()?)
}

/// True when every host is a loopback address or a Unix socket.
fn is_local(hosts: &[Host]) -> bool {
    hosts.iter().all(|host| match host {
        Host::Tcp(name) => matches!(name.as_str(), "localhost" | "127.0.0.1" | "::1" | "[::1]"),
        _ => true,
    })
}

/// TLS client config. A CA from the environment replaces the default roots, so only
/// the configured CA is trusted (for Aiven, its own CA).
fn tls_client_config(config: &Config) -> Result<ClientConfig, DbError> {
    let mut roots = RootCertStore::empty();

    let pem = match (&config.database_ca_cert, &config.database_ca_cert_file) {
        (Some(pem), _) => Some(pem.clone()),
        (None, Some(path)) => {
            Some(
                std::fs::read_to_string(path).map_err(|source| DbError::CaFileRead {
                    path: path.clone(),
                    source,
                })?,
            )
        }
        (None, None) => None,
    };

    match pem {
        Some(pem) => {
            let mut reader = pem.as_bytes();
            let mut found = 0;
            for cert in rustls_pemfile::certs(&mut reader) {
                let cert = cert.map_err(|_| DbError::CaPem)?;
                roots.add(cert).map_err(DbError::CaCert)?;
                found += 1;
            }
            if found == 0 {
                return Err(DbError::CaPem);
            }
        }
        None => {
            roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        }
    }

    Ok(ClientConfig::builder()
        .with_root_certificates(Arc::new(roots))
        .with_no_client_auth())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tcp(name: &str) -> Host {
        Host::Tcp(name.to_owned())
    }

    #[test]
    fn only_loopback_hosts_are_local() {
        assert!(is_local(&[tcp("localhost")]));
        assert!(is_local(&[tcp("127.0.0.1")]));
        assert!(is_local(&[tcp("::1")]));
        assert!(!is_local(&[tcp("localhost"), tcp("db.example.com")]));
        assert!(!is_local(&[tcp("ep-cool-123.aivencloud.com")]));
    }

    fn test_url() -> String {
        std::env::var("TEST_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres@localhost:5432/postgres".to_owned())
    }

    fn test_pool(url: &str) -> Pool {
        let config = Config::from_lookup(|key| match key {
            "DATABASE_URL" => Some(url.to_owned()),
            "JWT_SECRET" => Some("0123456789abcdef0123456789abcdef".to_owned()),
            _ => None,
        })
        .expect("config");
        create_pool(&config).expect("pool")
    }

    /// Needs a local Postgres. Run with:
    /// `TEST_DATABASE_URL=postgres://postgres@localhost:5432/postgres cargo test -- --ignored db::`
    #[tokio::test]
    #[ignore]
    async fn pool_connects_to_local_postgres() {
        let pool = test_pool(&test_url());
        let client = pool.get().await.expect("connection from pool");
        let row = client
            .query_one("SELECT 1::int4", &[])
            .await
            .expect("query");
        assert_eq!(row.get::<_, i32>(0), 1);
    }

    /// Runs the migrations twice on a scratch database `pw_mig_<uuid>`, then drops it.
    /// Needs Postgres 18 (see `pool_connects_to_local_postgres` for how to run).
    #[tokio::test]
    #[ignore]
    async fn migrations_apply_once_on_empty_database() {
        let admin_url = test_url();
        let admin = test_pool(&admin_url);
        let admin_client = admin.get().await.expect("admin connection");
        let name = format!("pw_mig_{}", uuid::Uuid::new_v4().simple());
        admin_client
            .batch_execute(&format!("CREATE DATABASE {name}"))
            .await
            .expect("create scratch database");

        let mut scratch_config = tokio_postgres::Config::from_str(&admin_url).expect("url");
        scratch_config.dbname(&name);
        let scratch = Manager::from_config(
            scratch_config,
            NoTls,
            ManagerConfig {
                recycling_method: RecyclingMethod::Fast,
            },
        );
        let scratch = Pool::builder(scratch).max_size(1).build().expect("pool");

        // Run the checks in a task so a failed assertion still reaches the cleanup below.
        let checks = tokio::spawn({
            let scratch = scratch.clone();
            async move {
                let first = run_migrations(&scratch).await.expect("first run");
                assert_eq!(first.len(), 1, "first run applies V1");
                let second = run_migrations(&scratch).await.expect("second run");
                assert!(second.is_empty(), "second run applies nothing");

                let client = scratch.get().await.expect("connection");
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
                let triggers =
                    count("SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal").await;
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

                let history = count("SELECT count(*) FROM refinery_schema_history").await;
                assert_eq!(history, 1);
            }
        })
        .await;

        scratch.close();
        admin_client
            .batch_execute(&format!("DROP DATABASE {name} WITH (FORCE)"))
            .await
            .expect("drop scratch database");

        if let Err(err) = checks {
            std::panic::resume_unwind(err.into_panic());
        }
    }
}
