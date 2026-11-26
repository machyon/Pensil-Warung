//! `POST /auth/register` and `POST /auth/login`.

use axum::Router;
use axum::extract::State;
use axum::routing::post;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::jwt::issue_token;
use super::password::hash_password;
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

pub fn routes() -> Router<AppState> {
    Router::new().route("/auth/register", post(register))
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

async fn register(
    State(state): State<AppState>,
    ApiJson(body): ApiJson<RegisterBody>,
) -> Result<Created<AuthResponse>, AppError> {
    body.validate()?;
    let email = normalize_email(&body.email)?;
    let display_name = sanitize_display_name(&body.display_name);
    let hash = hash_blocking(body.password).await?;

    let mut client = state.pool.get().await?;
    // The generated username can race with another signup: retry once on its unique key.
    let mut attempt = 0;
    let (id, role_id) = loop {
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
                "INSERT INTO auth_identities (user_id, provider, password_hash)
                 VALUES ($1, 'password', $2)",
                &[&id, &hash],
            )
            .await?;
            Ok::<_, AppError>((id, row.get::<_, i32>("role_id")))
        }
        .await;
        match inserted {
            Ok(ids) => {
                tx.commit().await?;
                break ids;
            }
            Err(err) if attempt < 2 && err.code() == ErrorCode::UsernameTaken => continue,
            Err(err) => return Err(err),
        }
    };

    let user = load_user(&client, &state.perms, id).await?;
    let token = token_for(&state, id, role_id)?;
    Ok(Created(AuthResponse { token, user }))
}
