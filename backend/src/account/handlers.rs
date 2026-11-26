//! `/me` endpoints. Every query is scoped to the authenticated user's id.
//! The PATCH routes return the updated user, the same shape as `GET /me`.

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::{get, patch, put};
use axum::{Json, Router};
use serde::Deserialize;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::auth::extractor::AuthUser;
use crate::auth::handlers::{check_password_len, hash_blocking, normalize_email};
use crate::auth::password::verify_password;
use crate::auth::user::{UserResponse, load_user};
use crate::common::extract::ApiJson;
use crate::common::names::sanitize_display_name;
use crate::common::response::NoContent;
use crate::common::validate::max_len;
use crate::error::{AppError, ErrorCode};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/me", get(me).delete(delete_me))
        .route("/me/username", patch(set_username))
        .route("/me/display-name", patch(set_display_name))
        .route("/me/email", patch(set_email))
        .route("/me/password", put(set_password))
}

async fn me(State(state): State<AppState>, user: AuthUser) -> Result<Json<UserResponse>, AppError> {
    let client = state.pool.get().await?;
    Ok(Json(load_user(&client, &state.perms, user.id).await?))
}

/// Runs one UPDATE of a single column on the caller's row, then returns the user.
/// `sql` takes `$1` = new value, `$2` = user id.
async fn update_and_load(
    state: &AppState,
    id: Uuid,
    sql: &str,
    value: &String,
) -> Result<Json<UserResponse>, AppError> {
    let client = state.pool.get().await?;
    if client.execute(sql, &[value, &id]).await? == 0 {
        return Err(AppError::new(ErrorCode::AccountGone));
    }
    Ok(Json(load_user(&client, &state.perms, id).await?))
}

#[derive(Deserialize)]
struct UsernameBody {
    username: String,
}

fn valid_username(s: &str) -> bool {
    (3..=30).contains(&s.len())
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
}

async fn set_username(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(body): ApiJson<UsernameBody>,
) -> Result<Json<UserResponse>, AppError> {
    if !valid_username(&body.username) {
        return Err(AppError::validation(
            ErrorCode::InvalidValue,
            "username",
            "Username 3-30 karakter: huruf kecil, angka, dan garis bawah.",
        ));
    }
    update_and_load(
        &state,
        user.id,
        "UPDATE users SET username = $1 WHERE id = $2",
        &body.username,
    )
    .await
}

#[derive(Deserialize)]
struct DisplayNameBody {
    display_name: String,
}

async fn set_display_name(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(body): ApiJson<DisplayNameBody>,
) -> Result<Json<UserResponse>, AppError> {
    max_len("display_name", &body.display_name, 100)?;
    let name = sanitize_display_name(&body.display_name)
        .filter(|n| n.chars().count() <= 50)
        .ok_or_else(|| {
            AppError::validation(
                ErrorCode::InvalidName,
                "display_name",
                "Nama 1-50 karakter: huruf, angka, dan spasi.",
            )
        })?;
    update_and_load(
        &state,
        user.id,
        "UPDATE users SET display_name = $1 WHERE id = $2",
        &name,
    )
    .await
}

/// Checks `current_password` against the user's password identity.
/// Google-only users get 403 `google_account`, a wrong password gets 401.
async fn check_current_password(
    client: &deadpool_postgres::Client,
    id: Uuid,
    current_password: String,
) -> Result<(), AppError> {
    max_len("current_password", &current_password, 128)?;
    let row = client
        .query_opt(
            "SELECT a.password_hash
               FROM users u
               LEFT JOIN auth_identities a ON a.user_id = u.id AND a.provider = 'password'
              WHERE u.id = $1",
            &[&id],
        )
        .await?
        .ok_or_else(|| AppError::new(ErrorCode::AccountGone))?;
    let hash: String = row
        .get::<_, Option<String>>("password_hash")
        .ok_or_else(|| AppError::new(ErrorCode::GoogleAccount))?;
    let ok = tokio::task::spawn_blocking(move || verify_password(&current_password, &hash))
        .await
        .map_err(|_| AppError::internal())?;
    if ok {
        Ok(())
    } else {
        Err(AppError::new(ErrorCode::InvalidCredentials).with_message("Kata sandi saat ini salah."))
    }
}

#[derive(Deserialize)]
struct EmailBody {
    email: String,
    current_password: String,
}

async fn set_email(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(body): ApiJson<EmailBody>,
) -> Result<Json<UserResponse>, AppError> {
    let email = normalize_email(&body.email)?;
    max_len("email", &email, 254)?;
    if !email.contains('@') {
        return Err(AppError::validation(
            ErrorCode::InvalidValue,
            "email",
            "Format email tidak valid.",
        ));
    }
    let client = state.pool.get().await?;
    check_current_password(&client, user.id, body.current_password).await?;
    drop(client);
    update_and_load(
        &state,
        user.id,
        "UPDATE users SET email = $1, token_version = token_version + 1 WHERE id = $2",
        &email,
    )
    .await
}

#[derive(Deserialize)]
struct PasswordBody {
    current_password: String,
    new_password: String,
}

async fn set_password(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(body): ApiJson<PasswordBody>,
) -> Result<NoContent, AppError> {
    check_password_len("new_password", &body.new_password)?;
    let client = state.pool.get().await?;
    check_current_password(&client, user.id, body.current_password).await?;
    let hash = hash_blocking(body.new_password).await?;
    client
        .execute(
            "WITH p AS (UPDATE auth_identities SET password_hash = $1
                          WHERE user_id = $2 AND provider = 'password' RETURNING 1)
             UPDATE users SET token_version = token_version + 1
              WHERE id = $2 AND EXISTS (SELECT 1 FROM p)",
            &[&hash, &user.id],
        )
        .await?;
    Ok(NoContent)
}

/// A Google token older than this (or issued this far in the future) is not a fresh sign-in.
const REAUTH_WINDOW_SECS: i64 = 300;
const REAUTH_SKEW_SECS: i64 = 60;

#[derive(Deserialize)]
struct DeleteBody {
    current_password: Option<String>,
    id_token: Option<String>,
}

fn reauth_required() -> AppError {
    AppError::new(ErrorCode::ReauthRequired)
}

/// Password users confirm with `current_password`, Google-only users with a fresh `id_token`.
/// The FK cascades remove the warung's data and the identities; broadcasts keep their rows.
async fn delete_me(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(body): ApiJson<DeleteBody>,
) -> Result<NoContent, AppError> {
    let client = state.pool.get().await?;
    let has_password = client
        .query_opt(
            "SELECT EXISTS (SELECT 1 FROM auth_identities
                             WHERE user_id = u.id AND provider = 'password')
               FROM users u WHERE u.id = $1",
            &[&user.id],
        )
        .await?
        .ok_or_else(|| AppError::new(ErrorCode::AccountGone))?
        .get::<_, bool>(0);
    if has_password {
        let password = body.current_password.ok_or_else(|| {
            AppError::validation(
                ErrorCode::InvalidValue,
                "current_password",
                "Kata sandi saat ini wajib diisi.",
            )
        })?;
        check_current_password(&client, user.id, password).await?;
    } else {
        let token = body.id_token.ok_or_else(reauth_required)?;
        let claims = state
            .google_keys
            .verify(
                &state.config.google_jwks_url,
                &state.config.google_client_ids,
                &token,
            )
            .await
            .map_err(|e| {
                if e.status() == StatusCode::UNAUTHORIZED {
                    reauth_required()
                } else {
                    e
                }
            })?;
        let age =
            OffsetDateTime::now_utc().unix_timestamp() - claims.iat.ok_or_else(reauth_required)?;
        let mine = client
            .query_opt(
                "SELECT 1 FROM auth_identities
                  WHERE user_id = $1 AND provider = 'google' AND provider_user_id = $2",
                &[&user.id, &claims.sub],
            )
            .await?
            .is_some();
        if !mine || !(-REAUTH_SKEW_SECS..=REAUTH_WINDOW_SECS).contains(&age) {
            return Err(reauth_required());
        }
    }
    client
        .execute("DELETE FROM users WHERE id = $1", &[&user.id])
        .await?;
    Ok(NoContent)
}
