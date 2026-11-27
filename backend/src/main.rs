use std::process::ExitCode;
use std::sync::Arc;

use clap::{Parser, Subcommand};
use tracing_subscriber::EnvFilter;

use backend::auth::perms::Permissions;
use backend::config::{AppEnv, Config};
use backend::state::AppState;
use backend::storage::{Storage, TigrisStorage};
use backend::{db, routes};

#[derive(Parser)]
#[command(name = "backend", about = "Pensil Warung API server")]
struct Cli {
    /// Defaults to `serve` when omitted.
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Run the HTTP server (default).
    Serve,
    /// Apply pending database migrations and exit.
    Migrate,
    /// Make the user with this email a broadcaster.
    Promote { email: String },
    /// Make the user with this email a normal user again.
    Demote { email: String },
}

#[tokio::main]
async fn main() -> ExitCode {
    let cli = Cli::parse();

    let config = match Config::from_env() {
        Ok(config) => config,
        Err(err) => {
            eprintln!("configuration error: {err}");
            return ExitCode::from(1);
        }
    };

    init_tracing(&config);
    if config.jwt_secret_generated {
        tracing::warn!(
            "JWT_SECRET is not set: generated a random development secret, \
             all tokens become invalid on restart"
        );
    }

    let result = match cli.command.unwrap_or(Command::Serve) {
        Command::Serve => serve(config).await,
        Command::Migrate => migrate(&config).await,
        Command::Promote { email } => set_role(&config, &email, 2).await,
        Command::Demote { email } => set_role(&config, &email, 1).await,
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            tracing::error!("{err}");
            ExitCode::from(1)
        }
    }
}

type AnyError = Box<dyn std::error::Error>;

fn init_tracing(config: &Config) {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(config.log_level.as_str()));
    let builder = tracing_subscriber::fmt().with_env_filter(filter);
    if config.app_env == AppEnv::Production {
        builder.json().init();
    } else {
        builder.compact().init();
    }
}

async fn migrate(config: &Config) -> Result<(), AnyError> {
    let pool = db::create_pool(config)?;
    let applied = db::run_migrations(&pool).await?;
    if applied.is_empty() {
        tracing::info!("database already up to date");
    }
    for migration in &applied {
        tracing::info!(
            version = migration.version(),
            name = migration.name(),
            "applied migration"
        );
    }
    Ok(())
}

/// Sets the role (1 user, 2 broadcaster). `token_version` is bumped in the same
/// UPDATE so the old JWT is rejected and the user logs in again with the new role.
async fn set_role(config: &Config, email: &str, role_id: i32) -> Result<(), AnyError> {
    let pool = db::create_pool(config)?;
    let client = pool.get().await?;
    let row = client
        .query_opt(
            "UPDATE users SET role_id = $2, token_version = token_version + 1
              WHERE email = lower($1) RETURNING email",
            &[&email.trim(), &role_id],
        )
        .await?
        .ok_or("no user with that email")?;
    let role = if role_id == 2 { "broadcaster" } else { "user" };
    println!("{} is now a {role}", row.get::<_, String>(0));
    Ok(())
}

async fn serve(config: Config) -> Result<(), AnyError> {
    let pool = db::create_pool(&config)?;
    let port = config.port;
    let perms = Arc::new(Permissions::load(&pool).await?);
    let storage = config
        .storage
        .as_ref()
        .map(|c| Arc::new(TigrisStorage::new(c)) as Arc<dyn Storage>);
    if storage.is_none() {
        tracing::warn!("Tigris is not configured: product photo routes return 503");
    }
    let state = AppState {
        pool,
        config: Arc::new(config),
        perms,
        google_keys: Arc::default(),
        storage,
    };
    let app = routes::router(state);

    let listener = tokio::net::TcpListener::bind(("0.0.0.0", port)).await?;
    tracing::info!(%port, "listening");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    tracing::info!("server stopped");
    Ok(())
}

/// Resolves on Ctrl-C or SIGTERM (Render sends SIGTERM on deploy).
async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };

    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(_) => std::future::pending::<()>().await,
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
    tracing::info!("shutdown signal received");
}
