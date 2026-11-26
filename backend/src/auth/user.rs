//! The `user` object returned by the auth endpoints and `GET /me`.

use deadpool_postgres::Client;
use serde::Serialize;
use uuid::Uuid;

use super::perms::Permissions;
use crate::error::{AppError, ErrorCode};

#[derive(Debug, Serialize)]
pub struct UserResponse {
    pub id: Uuid,
    pub display_name: String,
    pub username: String,
    pub email: String,
    /// Role name from `roles.name` ("user" or "broadcaster").
    pub role: String,
    pub permissions: Vec<&'static str>,
    pub has_password: bool,
}

/// Loads one user. A missing row means the account was deleted: 401 `account_gone`.
pub async fn load_user(
    client: &Client,
    perms: &Permissions,
    user_id: Uuid,
) -> Result<UserResponse, AppError> {
    let row = client
        .query_opt(
            "SELECT u.display_name, u.username, u.email, u.role_id, r.name AS role,
                    EXISTS (SELECT 1 FROM auth_identities a
                             WHERE a.user_id = u.id AND a.provider = 'password') AS has_password
               FROM users u JOIN roles r ON r.id = u.role_id
              WHERE u.id = $1",
            &[&user_id],
        )
        .await?
        .ok_or_else(|| AppError::new(ErrorCode::AccountGone))?;
    Ok(UserResponse {
        id: user_id,
        display_name: row.get("display_name"),
        username: row.get("username"),
        email: row.get("email"),
        role: row.get("role"),
        permissions: perms.names(row.get("role_id")),
        has_password: row.get("has_password"),
    })
}
