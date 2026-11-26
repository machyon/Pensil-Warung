//! `POST /auth/register`, `POST /auth/login` and `POST /auth/google`.

use std::sync::LazyLock;

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::jwt::issue_token;
use super::password::{hash_password, verify_password};
use super::user::{UserResponse, load_user};
use crate::common::extract::ApiJson;
use crate::common::names::sanitize_display_name;
use crate::common::response::Created;
use crate::common::validate::{Validate, max_len, trim_required};
use crate::error::{AppError, ErrorCode};
use crate::state::AppState;

const MIN_PASSWORD_CHARS: usize = 8;
/// Upper bound so a huge password cannot be used to burn Argon2 CPU.
const MAX_PASSWORD_CHARS: usize = 128;

/// Verified against when the email is unknown, so timing does not reveal it.
static DUMMY_HASH: LazyLock<String> =
    LazyLock::new(|| hash_password("dummy-password").unwrap_or_default());

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/google", post(google))
}

#[derive(Serialize)]
struct AuthResponse {
    token: String,
    user: UserResponse,
}

#[derive(Deserialize)]
struct RegisterBody {
    display_name: String,
    email: String,
    password: String,
}

impl Validate for RegisterBody {
    fn validate(&self) -> Result<(), AppError> {
        max_len("display_name", &self.display_name, 100)?;
        let email = normalize_email(&self.email)?;
        max_len("email", &email, 254)?;
        if !email.contains('@') {
            return Err(AppError::validation(
                ErrorCode::InvalidValue,
                "email",
                "Format email tidak valid.",
            ));
        }
        check_password_len(&self.password)
    }
}

#[derive(Deserialize)]
struct LoginBody {
    email: String,
    password: String,
}

fn normalize_email(raw: &str) -> Result<String, AppError> {
    Ok(trim_required("email", raw)?.to_lowercase())
}

fn check_password_len(password: &str) -> Result<(), AppError> {
    let len = password.chars().count();
    if len < MIN_PASSWORD_CHARS {
        return Err(AppError::validation(
            ErrorCode::InvalidValue,
            "password",
            format!("Kata sandi minimal {MIN_PASSWORD_CHARS} karakter."),
        ));
    }
    max_len("password", password, MAX_PASSWORD_CHARS)
}

fn token_for(state: &AppState, id: Uuid, role_id: i32) -> Result<String, AppError> {
    issue_token(
        &state.config.jwt_secret,
        id,
        role_id,
        state.config.jwt_expires_in,
    )
}

async fn hash_blocking(password: String) -> Result<String, AppError> {
    tokio::task::spawn_blocking(move || hash_password(&password))
        .await
        .map_err(|_| AppError::internal())?
}

/// Inserts a user and its login identity in one tx. The generated username can race
/// with another signup, so the insert is retried once on its unique key.
async fn create_user(
    client: &mut deadpool_postgres::Client,
    email: &str,
    display_name: Option<&str>,
    provider: &str,
    provider_user_id: Option<&str>,
    password_hash: Option<&str>,
) -> Result<(Uuid, i32), AppError> {
    let mut attempt = 0;
    loop {
        attempt += 1;
        let tx = client.transaction().await?;
        let inserted = async {
            let row = tx
                .query_one(
                    "INSERT INTO users (email, display_name) VALUES ($1, $2)
                     RETURNING id, role_id",
                    &[&email, &display_name],
                )
                .await?;
            let id: Uuid = row.get("id");
            tx.execute(
                "INSERT INTO auth_identities (user_id, provider, provider_user_id, password_hash)
                 VALUES ($1, $2::text::auth_provider, $3, $4)",
                &[&id, &provider, &provider_user_id, &password_hash],
            )
            .await?;
            Ok::<_, AppError>((id, row.get::<_, i32>("role_id")))
        }
        .await;
        match inserted {
            Ok(ids) => {
                tx.commit().await?;
                return Ok(ids);
            }
            Err(err) if attempt < 2 && err.code() == ErrorCode::UsernameTaken => continue,
            Err(err) => return Err(err),
        }
    }
}

async fn register(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<RegisterBody>,
) -> Result<Created<AuthResponse>, AppError> {
    body.validate()?;
    let email = normalize_email(&body.email)?;
    let display_name = sanitize_display_name(&body.display_name);
    let hash = hash_blocking(body.password).await?;

    let mut client = state.pool.get().await?;
    let (id, role_id) = create_user(
        &mut client,
        &email,
        display_name.as_deref(),
        "password",
        None,
        Some(&hash),
    )
    .await?;

    let user = load_user(&client, &state.perms, id).await?;
    let token = token_for(&state, id, role_id)?;
    Ok(Created(AuthResponse { token, user }))
}

async fn login(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<LoginBody>,
) -> Result<Json<AuthResponse>, AppError> {
    let email = normalize_email(&body.email)?;
    let client = state.pool.get().await?;
    let row = client
        .query_opt(
            "SELECT u.id, u.role_id, a.password_hash
               FROM users u
               LEFT JOIN auth_identities a ON a.user_id = u.id AND a.provider = 'password'
              WHERE u.email = $1",
            &[&email],
        )
        .await?;
    let found = row.as_ref().and_then(|r| {
        let hash: Option<String> = r.get("password_hash");
        Some((r.get::<_, Uuid>("id"), r.get::<_, i32>("role_id"), hash?))
    });
    // Unknown email and Google-only accounts still pay for one Argon2 verify.
    let stored = found
        .as_ref()
        .map_or_else(|| DUMMY_HASH.clone(), |(_, _, hash)| hash.clone());
    let password = body.password;
    let ok = tokio::task::spawn_blocking(move || verify_password(&password, &stored))
        .await
        .map_err(|_| AppError::internal())?;
    let (id, role_id) = match found {
        Some((id, role_id, _)) if ok => (id, role_id),
        _ => return Err(AppError::new(ErrorCode::InvalidCredentials)),
    };

    let user = load_user(&client, &state.perms, id).await?;
    let token = token_for(&state, id, role_id)?;
    Ok(Json(AuthResponse { token, user }))
}

#[derive(Deserialize)]
struct GoogleBody {
    id_token: String,
}

#[derive(Serialize)]
struct GoogleResponse {
    token: String,
    user: UserResponse,
    created: bool,
}

async fn google(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<GoogleBody>,
) -> Result<(StatusCode, Json<GoogleResponse>), AppError> {
    let claims = state
        .google_keys
        .verify(
            &state.config.google_jwks_url,
            &state.config.google_client_ids,
            &body.id_token,
        )
        .await?;
    let email = claims.email.trim().to_lowercase();

    let mut client = state.pool.get().await?;
    let known = client
        .query_opt(
            "SELECT u.id, u.role_id FROM auth_identities a JOIN users u ON u.id = a.user_id
              WHERE a.provider = 'google' AND a.provider_user_id = $1",
            &[&claims.sub],
        )
        .await?;
    let (id, role_id, created) = match known {
        Some(row) => (row.get("id"), row.get("role_id"), false),
        None => {
            // No account linking: an email that already has an account must sign in the old way.
            if client
                .query_opt("SELECT 1 FROM users WHERE email = $1", &[&email])
                .await?
                .is_some()
            {
                return Err(AppError::new(ErrorCode::EmailRegistered));
            }
            let display_name = claims.name.as_deref().and_then(sanitize_display_name);
            let (id, role_id) = create_user(
                &mut client,
                &email,
                display_name.as_deref(),
                "google",
                Some(&claims.sub),
                None,
            )
            .await?;
            (id, role_id, true)
        }
    };

    let user = load_user(&client, &state.perms, id).await?;
    let token = token_for(&state, id, role_id)?;
    let status = if created {
        StatusCode::CREATED
    } else {
        StatusCode::OK
    };
    Ok((
        status,
        Json(GoogleResponse {
            token,
            user,
            created,
        }),
    ))
}
