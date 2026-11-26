//! Google ID token verification against Google's JWKS, cached in memory.

use std::time::{Duration, Instant};

use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode, decode_header};
use serde::Deserialize;
use tokio::sync::Mutex;

use crate::error::AppError;

pub const GOOGLE_JWKS_URL: &str = "https://www.googleapis.com/oauth2/v3/certs";
const ISSUERS: [&str; 2] = ["accounts.google.com", "https://accounts.google.com"];
/// Used when the response has no usable `Cache-Control: max-age`.
const DEFAULT_TTL: Duration = Duration::from_secs(300);
/// An unknown `kid` triggers a refetch at most this often, so junk tokens cannot hammer Google.
const MIN_REFETCH: Duration = Duration::from_secs(60);

#[derive(Debug, Deserialize)]
pub struct GoogleClaims {
    pub sub: String,
    pub email: String,
    #[serde(default)]
    pub email_verified: bool,
    pub name: Option<String>,
}

#[derive(Default)]
struct Cached {
    keys: Option<JwkSet>,
    expires: Option<Instant>,
    fetched: Option<Instant>,
}

/// Process-wide JWKS cache. The URL is passed in (from config) so tests can point it at a mock.
#[derive(Default)]
pub struct GoogleKeys {
    cached: Mutex<Cached>,
    http: reqwest::Client,
}

impl GoogleKeys {
    /// Verifies signature (RS256), `iss`, `aud`, `exp` and `email_verified`. Every failure is 401.
    pub async fn verify(
        &self,
        jwks_url: &str,
        client_ids: &[String],
        id_token: &str,
    ) -> Result<GoogleClaims, AppError> {
        let bad = || AppError::unauthorized().with_message("Token Google tidak valid.");
        if client_ids.is_empty() {
            return Err(bad());
        }
        let header = decode_header(id_token).map_err(|_| bad())?;
        let kid = header.kid.ok_or_else(bad)?;
        let key = self.key(jwks_url, &kid).await?.ok_or_else(bad)?;

        let mut validation = Validation::new(Algorithm::RS256);
        validation.leeway = 0;
        validation.set_audience(client_ids);
        validation.set_issuer(&ISSUERS);
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);
        let claims = decode::<GoogleClaims>(id_token, &key, &validation)
            .map_err(|_| bad())?
            .claims;
        if !claims.email_verified {
            return Err(bad());
        }
        Ok(claims)
    }

    /// Looks up the key for `kid`, refetching when the cache is stale or the `kid` is unknown.
    async fn key(&self, url: &str, kid: &str) -> Result<Option<DecodingKey>, AppError> {
        let mut cached = self.cached.lock().await;
        let now = Instant::now();
        let fresh = cached.expires.is_some_and(|e| now < e);
        let find = |c: &Cached| {
            c.keys
                .as_ref()
                .and_then(|set| set.find(kid))
                .and_then(|jwk| DecodingKey::from_jwk(jwk).ok())
        };
        if fresh && let Some(key) = find(&cached) {
            return Ok(Some(key));
        }
        let may_refetch = !fresh || cached.fetched.is_none_or(|f| now - f >= MIN_REFETCH);
        if !may_refetch {
            return Ok(None);
        }
        let (keys, ttl) = self.fetch(url).await.map_err(|err| {
            tracing::error!(%err, "google jwks fetch failed");
            AppError::internal()
        })?;
        *cached = Cached {
            keys: Some(keys),
            expires: Some(now + ttl),
            fetched: Some(now),
        };
        Ok(find(&cached))
    }

    async fn fetch(&self, url: &str) -> Result<(JwkSet, Duration), reqwest::Error> {
        let res = self.http.get(url).send().await?.error_for_status()?;
        let ttl = res
            .headers()
            .get(reqwest::header::CACHE_CONTROL)
            .and_then(|v| v.to_str().ok())
            .and_then(max_age)
            .unwrap_or(DEFAULT_TTL);
        let bytes = res.bytes().await?;
        let set = serde_json::from_slice(&bytes).unwrap_or(JwkSet { keys: Vec::new() });
        Ok((set, ttl))
    }
}

fn max_age(cache_control: &str) -> Option<Duration> {
    cache_control
        .split(',')
        .find_map(|d| d.trim().strip_prefix("max-age="))
        .and_then(|v| v.parse().ok())
        .map(Duration::from_secs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_max_age() {
        assert_eq!(
            max_age("public, max-age=19535, must-revalidate"),
            Some(Duration::from_secs(19535))
        );
        assert_eq!(max_age("no-store"), None);
    }
}
