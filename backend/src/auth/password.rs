//! Argon2id password hashing (library defaults, random salt, PHC string output).

use argon2::password_hash::phc::PasswordHash;
use argon2::{Argon2, PasswordHasher, PasswordVerifier};

use crate::error::AppError;

/// Hashes a password into a PHC string such as `$argon2id$v=19$...`.
pub fn hash_password(password: &str) -> Result<String, AppError> {
    Argon2::default()
        .hash_password(password.as_bytes())
        .map(|hash| hash.to_string())
        .map_err(|err| {
            tracing::error!(%err, "password hashing failed");
            AppError::internal()
        })
}

/// True only when `password` matches `stored`. A malformed stored hash is false.
pub fn verify_password(password: &str, stored: &str) -> bool {
    let Ok(hash) = stored.parse::<PasswordHash>() else {
        return false;
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &hash)
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_roundtrip() {
        let hash = hash_password("rahasia123").unwrap();
        assert!(hash.starts_with("$argon2id$"));
        assert!(verify_password("rahasia123", &hash));
        assert!(!verify_password("rahasia124", &hash));
    }

    #[test]
    fn salts_differ_and_garbage_hash_is_rejected() {
        assert_ne!(
            hash_password("sama").unwrap(),
            hash_password("sama").unwrap()
        );
        assert!(!verify_password("x", "not-a-hash"));
    }
}
