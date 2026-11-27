//! Runtime configuration, read once from the environment at startup.
//!
//! The parsing logic lives in [`Config::from_lookup`], which takes a closure
//! instead of reading `std::env` directly, so tests never mutate process state.

use std::fmt;
use std::path::PathBuf;

use thiserror::Error;
use time::Duration;
use uuid::Uuid;

/// Minimum length of `JWT_SECRET`.
pub const JWT_SECRET_MIN_LEN: usize = 32;
/// Upper bound for presigned GET URLs (S3 allows at most 7 days).
const IMAGE_URL_TTL_MAX_SECONDS: u64 = 7 * 24 * 60 * 60;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("environment variable {key} is required")]
    Missing { key: &'static str },
    #[error("environment variable {key} is invalid: {reason}")]
    Invalid { key: &'static str, reason: String },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppEnv {
    Development,
    Production,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

impl LogLevel {
    pub fn as_str(self) -> &'static str {
        match self {
            LogLevel::Debug => "debug",
            LogLevel::Info => "info",
            LogLevel::Warn => "warn",
            LogLevel::Error => "error",
        }
    }
}

/// Tigris (S3) settings. Present only when the bucket and both keys are set.
#[derive(Clone)]
pub struct StorageConfig {
    /// Optional custom endpoint. The AWS SDK also reads `AWS_ENDPOINT_URL_S3` itself.
    pub endpoint_url: Option<String>,
    pub region: String,
    pub access_key_id: String,
    pub secret_access_key: String,
    pub bucket: String,
    /// Lifetime of presigned GET URLs for stored images.
    pub image_url_ttl: std::time::Duration,
}

#[derive(Clone)]
pub struct Config {
    pub app_env: AppEnv,
    pub port: u16,
    pub log_level: LogLevel,

    pub database_url: String,
    /// PEM contents of the CA certificate (`DATABASE_CA_CERT`).
    pub database_ca_cert: Option<String>,
    /// Path to a CA certificate file (`DATABASE_CA_CERT_FILE`), raw as given.
    /// Default-file resolution happens in `db.rs`.
    pub database_ca_cert_file: Option<PathBuf>,
    pub database_pool_max: usize,

    pub jwt_secret: String,
    /// True when no secret was configured in development and a random one was generated.
    /// The caller should warn, because every token becomes invalid on restart.
    pub jwt_secret_generated: bool,
    pub jwt_expires_in: Duration,

    /// Accepted Google OAuth client ids (Android, iOS, web). May be empty until Google login is used.
    pub google_client_ids: Vec<String>,
    /// Where Google's signing keys are fetched from (`GOOGLE_JWKS_URL`). Tests point it at a mock.
    pub google_jwks_url: String,

    pub storage: Option<StorageConfig>,
}

impl Config {
    /// Loads `.env` (if present) and then reads the process environment.
    pub fn from_env() -> Result<Self, ConfigError> {
        let _ = dotenvy::dotenv();
        Self::from_lookup(|key| std::env::var(key).ok())
    }

    /// Builds the config from any key lookup. Empty values count as unset.
    pub fn from_lookup<F>(lookup: F) -> Result<Self, ConfigError>
    where
        F: Fn(&str) -> Option<String>,
    {
        let get = |key: &str| {
            lookup(key)
                .map(|v| v.trim().to_owned())
                .filter(|v| !v.is_empty())
        };

        let app_env = match get("APP_ENV").as_deref() {
            None | Some("development") => AppEnv::Development,
            Some("production") => AppEnv::Production,
            Some(other) => {
                return Err(invalid(
                    "APP_ENV",
                    format!("expected development or production, got {other:?}"),
                ));
            }
        };

        let port = match get("PORT") {
            None => 3000,
            Some(v) => v
                .parse::<u16>()
                .map_err(|_| invalid("PORT", "expected a port number from 0 to 65535"))?,
        };

        let log_level = match get("LOG_LEVEL").as_deref() {
            None | Some("info") => LogLevel::Info,
            Some("debug") => LogLevel::Debug,
            Some("warn") => LogLevel::Warn,
            Some("error") => LogLevel::Error,
            Some(other) => {
                return Err(invalid(
                    "LOG_LEVEL",
                    format!("expected debug, info, warn or error, got {other:?}"),
                ));
            }
        };

        let database_url = get("DATABASE_URL").ok_or(ConfigError::Missing {
            key: "DATABASE_URL",
        })?;
        let database_ca_cert = get("DATABASE_CA_CERT");
        let database_ca_cert_file = get("DATABASE_CA_CERT_FILE").map(PathBuf::from);

        let database_pool_max = match get("DATABASE_POOL_MAX") {
            None => 5,
            Some(v) => match v.parse::<usize>() {
                Ok(n) if n >= 1 => n,
                _ => {
                    return Err(invalid(
                        "DATABASE_POOL_MAX",
                        "expected an integer of at least 1",
                    ));
                }
            },
        };

        let (jwt_secret, jwt_secret_generated) = resolve_jwt_secret(app_env, get("JWT_SECRET"))?;

        let jwt_expires_in = match get("JWT_EXPIRES_IN") {
            None => Duration::days(7),
            Some(v) => parse_duration(&v).map_err(|reason| invalid("JWT_EXPIRES_IN", reason))?,
        };

        let google_client_ids = get("GOOGLE_CLIENT_IDS")
            .map(|v| parse_client_ids(&v))
            .unwrap_or_default();

        let google_jwks_url = get("GOOGLE_JWKS_URL")
            .unwrap_or_else(|| crate::auth::google::GOOGLE_JWKS_URL.to_owned());

        let storage = resolve_storage(&get)?;

        Ok(Config {
            app_env,
            port,
            log_level,
            database_url,
            database_ca_cert,
            database_ca_cert_file,
            database_pool_max,
            jwt_secret,
            jwt_secret_generated,
            jwt_expires_in,
            google_client_ids,
            google_jwks_url,
            storage,
        })
    }
}

/// Production needs a configured secret of at least 32 characters. Development
/// generates a random one when none is set. A configured secret must be at
/// least 32 characters in every environment, because a shorter one is never
/// intended.
fn resolve_jwt_secret(
    app_env: AppEnv,
    configured: Option<String>,
) -> Result<(String, bool), ConfigError> {
    match configured {
        Some(secret) if secret.chars().count() >= JWT_SECRET_MIN_LEN => Ok((secret, false)),
        Some(_) => Err(invalid(
            "JWT_SECRET",
            format!("must be at least {JWT_SECRET_MIN_LEN} characters"),
        )),
        None if app_env == AppEnv::Production => Err(invalid(
            "JWT_SECRET",
            format!("required in production, at least {JWT_SECRET_MIN_LEN} characters"),
        )),
        None => Ok((random_secret(), true)),
    }
}

/// 64 hex characters built from two v4 UUIDs (about 244 random bits).
fn random_secret() -> String {
    format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple())
}

/// Parses `<n><unit>` with unit `s`, `m`, `h` or `d`, for example `7d` or `12h`.
pub fn parse_duration(input: &str) -> Result<Duration, String> {
    let input = input.trim();
    let unit_pos = input
        .find(|c: char| !c.is_ascii_digit())
        .ok_or_else(|| format!("{input:?} has no unit, use s, m, h or d such as 7d"))?;
    let (digits, unit) = input.split_at(unit_pos);

    let amount: i64 = digits
        .parse()
        .map_err(|_| format!("{input:?} is not a duration such as 7d or 12h"))?;
    if amount <= 0 {
        return Err(format!("{input:?} must be greater than zero"));
    }

    let seconds_per_unit: i64 = match unit {
        "s" => 1,
        "m" => 60,
        "h" => 60 * 60,
        "d" => 24 * 60 * 60,
        _ => return Err(format!("{input:?} has an unknown unit, use s, m, h or d")),
    };
    let seconds = amount
        .checked_mul(seconds_per_unit)
        .ok_or_else(|| format!("{input:?} is too large"))?;
    Ok(Duration::seconds(seconds))
}

/// Splits a comma-separated list, trimming spaces and dropping empty entries.
pub fn parse_client_ids(input: &str) -> Vec<String> {
    input
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect()
}

fn resolve_storage<F>(get: &F) -> Result<Option<StorageConfig>, ConfigError>
where
    F: Fn(&str) -> Option<String>,
{
    let bucket = get("TIGRIS_BUCKET");
    let access_key_id = get("AWS_ACCESS_KEY_ID");
    let secret_access_key = get("AWS_SECRET_ACCESS_KEY");

    // Storage is either fully configured or not used at all.
    let (bucket, access_key_id, secret_access_key) =
        match (bucket, access_key_id, secret_access_key) {
            (None, None, None) => {
                // The TTL is still validated when it is set, so a typo fails at startup.
                ttl_from(get)?;
                return Ok(None);
            }
            (Some(b), Some(k), Some(s)) => (b, k, s),
            (b, k, _) => {
                let missing = if b.is_none() {
                    "TIGRIS_BUCKET"
                } else if k.is_none() {
                    "AWS_ACCESS_KEY_ID"
                } else {
                    "AWS_SECRET_ACCESS_KEY"
                };
                return Err(invalid(
                    "TIGRIS_BUCKET",
                    format!("storage is partly configured, {missing} is missing"),
                ));
            }
        };

    Ok(Some(StorageConfig {
        endpoint_url: get("AWS_ENDPOINT_URL_S3"),
        region: get("AWS_REGION").unwrap_or_else(|| "auto".to_owned()),
        access_key_id,
        secret_access_key,
        bucket,
        image_url_ttl: ttl_from(get)?,
    }))
}

fn ttl_from<F>(get: &F) -> Result<std::time::Duration, ConfigError>
where
    F: Fn(&str) -> Option<String>,
{
    let seconds = match get("IMAGE_URL_TTL_SECONDS") {
        None => 3600,
        Some(v) => match v.parse::<u64>() {
            Ok(n) if (1..=IMAGE_URL_TTL_MAX_SECONDS).contains(&n) => n,
            _ => {
                return Err(invalid(
                    "IMAGE_URL_TTL_SECONDS",
                    format!("expected a whole number from 1 to {IMAGE_URL_TTL_MAX_SECONDS}"),
                ));
            }
        },
    };
    Ok(std::time::Duration::from_secs(seconds))
}

fn invalid(key: &'static str, reason: impl Into<String>) -> ConfigError {
    ConfigError::Invalid {
        key,
        reason: reason.into(),
    }
}

// Manual Debug so that secrets never end up in logs.
impl fmt::Debug for Config {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Config")
            .field("app_env", &self.app_env)
            .field("port", &self.port)
            .field("log_level", &self.log_level)
            .field("database_url", &"<redacted>")
            .field(
                "database_ca_cert",
                &self.database_ca_cert.as_ref().map(|_| "<redacted>"),
            )
            .field("database_ca_cert_file", &self.database_ca_cert_file)
            .field("database_pool_max", &self.database_pool_max)
            .field("jwt_secret", &"<redacted>")
            .field("jwt_secret_generated", &self.jwt_secret_generated)
            .field("jwt_expires_in", &self.jwt_expires_in)
            .field("google_client_ids", &self.google_client_ids)
            .field(
                "storage",
                &self.storage.as_ref().map(StorageConfig::redacted_debug),
            )
            .finish()
    }
}

impl StorageConfig {
    fn redacted_debug(&self) -> String {
        format!(
            "StorageConfig {{ endpoint_url: {:?}, region: {:?}, bucket: {:?}, access_key_id: <redacted>, secret_access_key: <redacted>, image_url_ttl: {:?} }}",
            self.endpoint_url, self.region, self.bucket, self.image_url_ttl
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn lookup(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        move |key| map.get(key).cloned()
    }

    const SECRET_32: &str = "0123456789abcdef0123456789abcdef";

    #[test]
    fn parses_durations() {
        assert_eq!(parse_duration("7d"), Ok(Duration::days(7)));
        assert_eq!(parse_duration("12h"), Ok(Duration::hours(12)));
        assert_eq!(parse_duration("30m"), Ok(Duration::minutes(30)));
        assert_eq!(parse_duration("90s"), Ok(Duration::seconds(90)));
        assert_eq!(parse_duration(" 2d "), Ok(Duration::days(2)));
    }

    #[test]
    fn rejects_bad_durations() {
        for bad in [
            "",
            "7",
            "d",
            "0d",
            "-1h",
            "1w",
            "abc",
            "1.5h",
            "99999999999999999999d",
        ] {
            assert!(parse_duration(bad).is_err(), "{bad:?} should be rejected");
        }
    }

    #[test]
    fn parses_client_ids() {
        assert_eq!(
            parse_client_ids("android.apps, ios.apps ,,web.apps,"),
            vec!["android.apps", "ios.apps", "web.apps"]
        );
        assert!(parse_client_ids("  , ").is_empty());
    }

    #[test]
    fn production_requires_long_secret() {
        let missing = Config::from_lookup(lookup(&[
            ("APP_ENV", "production"),
            ("DATABASE_URL", "postgres://x"),
        ]));
        assert!(matches!(
            missing,
            Err(ConfigError::Invalid {
                key: "JWT_SECRET",
                ..
            })
        ));

        let short = Config::from_lookup(lookup(&[
            ("APP_ENV", "production"),
            ("DATABASE_URL", "postgres://x"),
            ("JWT_SECRET", "too-short"),
        ]));
        assert!(matches!(
            short,
            Err(ConfigError::Invalid {
                key: "JWT_SECRET",
                ..
            })
        ));

        let ok = Config::from_lookup(lookup(&[
            ("APP_ENV", "production"),
            ("DATABASE_URL", "postgres://x"),
            ("JWT_SECRET", SECRET_32),
        ]))
        .unwrap();
        assert_eq!(ok.app_env, AppEnv::Production);
        assert_eq!(ok.jwt_secret, SECRET_32);
        assert!(!ok.jwt_secret_generated);
    }

    #[test]
    fn development_generates_secret_when_unset() {
        let cfg = Config::from_lookup(lookup(&[("DATABASE_URL", "postgres://x")])).unwrap();
        assert_eq!(cfg.app_env, AppEnv::Development);
        assert_eq!(cfg.jwt_secret.len(), 64);
        assert!(cfg.jwt_secret_generated);

        let other = Config::from_lookup(lookup(&[("DATABASE_URL", "postgres://x")])).unwrap();
        assert_ne!(cfg.jwt_secret, other.jwt_secret);
    }

    #[test]
    fn empty_values_count_as_unset() {
        let cfg = Config::from_lookup(lookup(&[
            ("DATABASE_URL", "postgres://x"),
            ("JWT_SECRET", ""),
            ("DATABASE_CA_CERT", "  "),
            ("GOOGLE_CLIENT_IDS", ""),
        ]))
        .unwrap();
        assert!(cfg.jwt_secret_generated);
        assert!(cfg.database_ca_cert.is_none());
        assert!(cfg.google_client_ids.is_empty());
    }

    #[test]
    fn defaults_and_overrides() {
        let cfg = Config::from_lookup(lookup(&[("DATABASE_URL", "postgres://x")])).unwrap();
        assert_eq!(cfg.port, 3000);
        assert_eq!(cfg.log_level, LogLevel::Info);
        assert_eq!(cfg.database_pool_max, 5);
        assert_eq!(cfg.jwt_expires_in, Duration::days(7));
        assert!(cfg.storage.is_none());

        let cfg = Config::from_lookup(lookup(&[
            ("DATABASE_URL", "postgres://x"),
            ("PORT", "8080"),
            ("LOG_LEVEL", "debug"),
            ("DATABASE_POOL_MAX", "10"),
            ("JWT_EXPIRES_IN", "12h"),
            ("GOOGLE_CLIENT_IDS", "a.apps,b.apps"),
        ]))
        .unwrap();
        assert_eq!(cfg.port, 8080);
        assert_eq!(cfg.log_level, LogLevel::Debug);
        assert_eq!(cfg.database_pool_max, 10);
        assert_eq!(cfg.jwt_expires_in, Duration::hours(12));
        assert_eq!(cfg.google_client_ids, vec!["a.apps", "b.apps"]);
    }

    #[test]
    fn rejects_invalid_values() {
        let base = [("DATABASE_URL", "postgres://x")];
        let cases: Vec<Vec<(&str, &str)>> = vec![
            vec![("APP_ENV", "staging")],
            vec![("PORT", "99999")],
            vec![("LOG_LEVEL", "verbose")],
            vec![("DATABASE_POOL_MAX", "0")],
            vec![("JWT_EXPIRES_IN", "forever")],
            vec![("IMAGE_URL_TTL_SECONDS", "0")],
        ];
        for extra in cases {
            let mut pairs = base.to_vec();
            pairs.extend(extra.iter().copied());
            assert!(
                matches!(
                    Config::from_lookup(lookup(&pairs)),
                    Err(ConfigError::Invalid { .. })
                ),
                "{extra:?} should be rejected"
            );
        }
    }

    #[test]
    fn database_url_is_required() {
        assert_eq!(
            Config::from_lookup(lookup(&[])).err(),
            Some(ConfigError::Missing {
                key: "DATABASE_URL"
            })
        );
    }

    #[test]
    fn partial_storage_config_is_rejected() {
        let result = Config::from_lookup(lookup(&[
            ("DATABASE_URL", "postgres://x"),
            ("TIGRIS_BUCKET", "pensil-warung"),
        ]));
        assert!(matches!(result, Err(ConfigError::Invalid { .. })));

        let full = Config::from_lookup(lookup(&[
            ("DATABASE_URL", "postgres://x"),
            ("TIGRIS_BUCKET", "pensil-warung"),
            ("AWS_ACCESS_KEY_ID", "key"),
            ("AWS_SECRET_ACCESS_KEY", "secret"),
        ]))
        .unwrap();
        let storage = full.storage.unwrap();
        assert_eq!(storage.region, "auto");
        assert_eq!(storage.image_url_ttl, std::time::Duration::from_secs(3600));
    }

    #[test]
    fn debug_output_hides_secrets() {
        let cfg = Config::from_lookup(lookup(&[
            ("DATABASE_URL", "postgres://user:hunter2@host/db"),
            ("JWT_SECRET", SECRET_32),
        ]))
        .unwrap();
        let text = format!("{cfg:?}");
        assert!(!text.contains("hunter2"));
        assert!(!text.contains(SECRET_32));
    }
}
