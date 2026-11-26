//! HS256 access tokens. Claims: `sub` (user id), `role` (role id), `iat`, `exp`.

use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::error::AppError;

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,
    pub role: i32,
    pub iat: i64,
    pub exp: i64,
}

/// Signs a token for `user_id` that expires `expires_in` from now.
pub fn issue_token(
    secret: &str,
    user_id: Uuid,
    role_id: i32,
    expires_in: Duration,
) -> Result<String, AppError> {
    let now = OffsetDateTime::now_utc();
    let claims = Claims {
        sub: user_id,
        role: role_id,
        iat: now.unix_timestamp(),
        exp: (now + expires_in).unix_timestamp(),
    };
    EncodingKey::from_secret(secret.as_bytes())
        .and_then(|key| encode(&Header::new(Algorithm::HS256), &claims, &key))
        .map_err(|err| {
            tracing::error!(%err, "jwt signing failed");
            AppError::internal()
        })
}

/// Checks signature, algorithm and expiry. Every failure is 401 `unauthorized`.
pub fn verify_token(secret: &str, token: &str) -> Result<Claims, AppError> {
    let mut validation = Validation::new(Algorithm::HS256);
    validation.leeway = 0;
    validation.set_required_spec_claims(&["exp", "sub"]);
    DecodingKey::from_secret(secret.as_bytes())
        .and_then(|key| decode::<Claims>(token, &key, &validation))
        .map(|data| data.claims)
        .map_err(|_| AppError::unauthorized())
}

#[cfg(test)]
mod tests {
    use super::*;

    const SECRET: &str = "pensil-warung-test-jwt-secret-0123456789";

    #[test]
    fn roundtrip() {
        let id = Uuid::new_v4();
        let token = issue_token(SECRET, id, 2, Duration::days(7)).unwrap();
        let claims = verify_token(SECRET, &token).unwrap();
        assert_eq!((claims.sub, claims.role), (id, 2));
        assert_eq!(claims.exp - claims.iat, 7 * 24 * 3600);
    }

    #[test]
    fn expired_token_is_unauthorized() {
        let token = issue_token(SECRET, Uuid::new_v4(), 1, Duration::seconds(-10)).unwrap();
        assert_eq!(
            verify_token(SECRET, &token).unwrap_err().code(),
            crate::error::ErrorCode::Unauthorized
        );
    }

    #[test]
    fn tampered_wrong_key_and_garbage_are_unauthorized() {
        let token = issue_token(SECRET, Uuid::new_v4(), 1, Duration::days(1)).unwrap();
        let mut parts: Vec<&str> = token.split('.').collect();
        parts[2] = "AAAA";
        assert!(verify_token(SECRET, &parts.join(".")).is_err());
        assert!(verify_token("another-secret-another-secret-123456", &token).is_err());
        assert!(verify_token(SECRET, "nope").is_err());
    }
}
