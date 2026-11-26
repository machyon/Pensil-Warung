//! API errors. Every failed response has the shape
//! `{"error":{"code","message","details"?}}`, with an Indonesian `message`.

use std::borrow::Cow;

use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use serde_json::json;

pub type AppResult<T> = Result<T, AppError>;

/// Machine-readable error codes. The wire string is the snake_case name.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    InvalidBody,
    InvalidQuery,
    InvalidPath,
    InvalidValue,
    InvalidName,
    NotFound,
    Unauthorized,
    InvalidCredentials,
    Forbidden,
    AccountGone,
    EmailTaken,
    UsernameTaken,
    NameTaken,
    EmailRegistered,
    GoogleAccount,
    ReauthRequired,
    StockInsufficient,
    NothingToUpdate,
    NotEditable,
    TimePassed,
    PayloadTooLarge,
    UnsupportedImage,
    StorageUnavailable,
    DbUnavailable,
    Internal,
}

impl ErrorCode {
    /// The wire string, the same as the serde name.
    pub fn as_str(self) -> &'static str {
        match self {
            ErrorCode::InvalidBody => "invalid_body",
            ErrorCode::InvalidQuery => "invalid_query",
            ErrorCode::InvalidPath => "invalid_path",
            ErrorCode::InvalidValue => "invalid_value",
            ErrorCode::InvalidName => "invalid_name",
            ErrorCode::NotFound => "not_found",
            ErrorCode::Unauthorized => "unauthorized",
            ErrorCode::InvalidCredentials => "invalid_credentials",
            ErrorCode::Forbidden => "forbidden",
            ErrorCode::AccountGone => "account_gone",
            ErrorCode::EmailTaken => "email_taken",
            ErrorCode::UsernameTaken => "username_taken",
            ErrorCode::NameTaken => "name_taken",
            ErrorCode::EmailRegistered => "email_registered",
            ErrorCode::GoogleAccount => "google_account",
            ErrorCode::ReauthRequired => "reauth_required",
            ErrorCode::StockInsufficient => "stock_insufficient",
            ErrorCode::NothingToUpdate => "nothing_to_update",
            ErrorCode::NotEditable => "not_editable",
            ErrorCode::TimePassed => "time_passed",
            ErrorCode::PayloadTooLarge => "payload_too_large",
            ErrorCode::UnsupportedImage => "unsupported_image",
            ErrorCode::StorageUnavailable => "storage_unavailable",
            ErrorCode::DbUnavailable => "db_unavailable",
            ErrorCode::Internal => "internal",
        }
    }

    /// Default HTTP status and Indonesian message for each code.
    fn defaults(self) -> (StatusCode, &'static str) {
        match self {
            ErrorCode::InvalidBody => (StatusCode::BAD_REQUEST, "Isi permintaan tidak valid."),
            ErrorCode::InvalidQuery => {
                (StatusCode::BAD_REQUEST, "Parameter permintaan tidak valid.")
            }
            ErrorCode::InvalidPath => (StatusCode::BAD_REQUEST, "Alamat permintaan tidak valid."),
            ErrorCode::InvalidValue => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "Nilai yang dimasukkan tidak valid.",
            ),
            ErrorCode::InvalidName => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "Nama yang dimasukkan tidak valid.",
            ),
            ErrorCode::NotFound => (StatusCode::NOT_FOUND, "Data tidak ditemukan."),
            ErrorCode::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                "Sesi Anda telah berakhir. Silakan masuk kembali.",
            ),
            ErrorCode::InvalidCredentials => {
                (StatusCode::UNAUTHORIZED, "Email atau kata sandi salah.")
            }
            ErrorCode::Forbidden => (
                StatusCode::FORBIDDEN,
                "Anda tidak memiliki akses untuk tindakan ini.",
            ),
            ErrorCode::AccountGone => (
                StatusCode::UNAUTHORIZED,
                "Akun tidak ditemukan. Silakan masuk kembali.",
            ),
            ErrorCode::EmailTaken => (StatusCode::CONFLICT, "Email sudah digunakan."),
            ErrorCode::UsernameTaken => (StatusCode::CONFLICT, "Username sudah digunakan."),
            ErrorCode::NameTaken => (StatusCode::CONFLICT, "Nama produk sudah digunakan."),
            ErrorCode::EmailRegistered => (
                StatusCode::CONFLICT,
                "Email ini sudah terdaftar. Silakan masuk dengan kata sandi.",
            ),
            ErrorCode::GoogleAccount => (
                StatusCode::FORBIDDEN,
                "Akun ini masuk dengan Google, sehingga tidak dapat diubah di sini.",
            ),
            ErrorCode::ReauthRequired => (
                StatusCode::UNAUTHORIZED,
                "Silakan verifikasi ulang akun Anda untuk melanjutkan.",
            ),
            ErrorCode::StockInsufficient => (StatusCode::UNPROCESSABLE_ENTITY, "Stok tidak cukup."),
            ErrorCode::NothingToUpdate => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "Tidak ada data yang diubah.",
            ),
            ErrorCode::NotEditable => (StatusCode::CONFLICT, "Data ini tidak dapat diubah."),
            ErrorCode::TimePassed => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "Waktu untuk tindakan ini sudah lewat.",
            ),
            ErrorCode::PayloadTooLarge => (
                StatusCode::PAYLOAD_TOO_LARGE,
                "Ukuran berkas terlalu besar.",
            ),
            ErrorCode::UnsupportedImage => (
                StatusCode::UNSUPPORTED_MEDIA_TYPE,
                "Foto harus berformat JPEG, PNG, atau WebP.",
            ),
            ErrorCode::StorageUnavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Penyimpanan foto belum tersedia.",
            ),
            ErrorCode::DbUnavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Layanan sedang tidak tersedia. Coba lagi sebentar.",
            ),
            ErrorCode::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Terjadi kesalahan pada server.",
            ),
        }
    }
}

#[derive(Debug)]
pub struct AppError {
    status: StatusCode,
    code: ErrorCode,
    message: Cow<'static, str>,
    details: Option<serde_json::Value>,
}

impl AppError {
    /// An error with the code's default status and message.
    pub fn new(code: ErrorCode) -> Self {
        let (status, message) = code.defaults();
        Self {
            status,
            code,
            message: Cow::Borrowed(message),
            details: None,
        }
    }

    pub fn with_message(mut self, message: impl Into<Cow<'static, str>>) -> Self {
        self.message = message.into();
        self
    }

    pub fn with_details(mut self, details: serde_json::Value) -> Self {
        self.details = Some(details);
        self
    }

    /// Overrides the default status, for example 409 for an unknown unique index.
    pub fn with_status(mut self, status: StatusCode) -> Self {
        self.status = status;
        self
    }

    /// A validation error about one field: `details` is `{ "field": field }`.
    pub fn validation(code: ErrorCode, field: &str, message: impl Into<Cow<'static, str>>) -> Self {
        Self::new(code)
            .with_message(message)
            .with_details(json!({ "field": field }))
    }

    pub fn not_found() -> Self {
        Self::new(ErrorCode::NotFound)
    }

    pub fn unauthorized() -> Self {
        Self::new(ErrorCode::Unauthorized)
    }

    pub fn forbidden() -> Self {
        Self::new(ErrorCode::Forbidden)
    }

    pub fn db_unavailable() -> Self {
        Self::new(ErrorCode::DbUnavailable)
    }

    pub fn internal() -> Self {
        Self::new(ErrorCode::Internal)
    }

    pub fn status(&self) -> StatusCode {
        self.status
    }

    pub fn code(&self) -> ErrorCode {
        self.code
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let mut error = json!({
            "code": self.code.as_str(),
            "message": self.message,
        });
        if let Some(details) = self.details {
            error["details"] = details;
        }
        (self.status, Json(json!({ "error": error }))).into_response()
    }
}

/// Maps a PostgreSQL SQLSTATE and the violated constraint name to an error.
/// Pure, so the mapping can be tested without a database.
fn map_sql_state(code: &str, constraint: Option<&str>) -> AppError {
    match (code, constraint) {
        ("23505", Some("users_email_key")) => AppError::new(ErrorCode::EmailTaken),
        ("23505", Some("users_username_key")) => AppError::new(ErrorCode::UsernameTaken),
        ("23505", Some("products_user_name_key")) => AppError::new(ErrorCode::NameTaken),
        ("23505", _) => AppError::new(ErrorCode::InvalidValue).with_status(StatusCode::CONFLICT),
        ("23514", Some("products_stock_nonneg")) => AppError::new(ErrorCode::StockInsufficient),
        ("23514", _) => AppError::new(ErrorCode::InvalidValue),
        ("23503", _) => AppError::new(ErrorCode::AccountGone),
        _ => {
            tracing::error!(sqlstate = code, constraint, "unmapped database error");
            AppError::internal()
        }
    }
}

impl From<tokio_postgres::Error> for AppError {
    fn from(err: tokio_postgres::Error) -> Self {
        match err.code() {
            Some(state) => {
                let constraint = err.as_db_error().and_then(|db| db.constraint());
                map_sql_state(state.code(), constraint)
            }
            None if err.is_closed() => {
                tracing::warn!(error = %err, "database connection closed");
                AppError::db_unavailable()
            }
            None => {
                tracing::error!(error = %err, "database call failed without an SQLSTATE");
                AppError::internal()
            }
        }
    }
}

impl From<deadpool_postgres::PoolError> for AppError {
    fn from(err: deadpool_postgres::PoolError) -> Self {
        tracing::warn!(error = %err, "could not get a database connection");
        AppError::db_unavailable()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;

    const ALL: [ErrorCode; 25] = [
        ErrorCode::InvalidBody,
        ErrorCode::InvalidQuery,
        ErrorCode::InvalidPath,
        ErrorCode::InvalidValue,
        ErrorCode::InvalidName,
        ErrorCode::NotFound,
        ErrorCode::Unauthorized,
        ErrorCode::InvalidCredentials,
        ErrorCode::Forbidden,
        ErrorCode::AccountGone,
        ErrorCode::EmailTaken,
        ErrorCode::UsernameTaken,
        ErrorCode::NameTaken,
        ErrorCode::EmailRegistered,
        ErrorCode::GoogleAccount,
        ErrorCode::ReauthRequired,
        ErrorCode::StockInsufficient,
        ErrorCode::NothingToUpdate,
        ErrorCode::NotEditable,
        ErrorCode::TimePassed,
        ErrorCode::PayloadTooLarge,
        ErrorCode::UnsupportedImage,
        ErrorCode::StorageUnavailable,
        ErrorCode::DbUnavailable,
        ErrorCode::Internal,
    ];

    async fn body_json(err: AppError) -> (StatusCode, serde_json::Value) {
        let response = err.into_response();
        let status = response.status();
        let bytes = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("body");
        (status, serde_json::from_slice(&bytes).expect("json"))
    }

    #[tokio::test]
    async fn response_has_error_envelope_without_details() {
        let (status, json) = body_json(AppError::not_found()).await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        assert_eq!(
            json,
            json!({ "error": { "code": "not_found", "message": "Data tidak ditemukan." } })
        );
    }

    #[tokio::test]
    async fn response_includes_details_when_set() {
        let err = AppError::validation(
            ErrorCode::InvalidValue,
            "price",
            "Harga harus lebih dari 0.",
        );
        let (status, json) = body_json(err).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(json["error"]["code"], "invalid_value");
        assert_eq!(json["error"]["message"], "Harga harus lebih dari 0.");
        assert_eq!(json["error"]["details"], json!({ "field": "price" }));
    }

    #[test]
    fn serde_name_matches_as_str_and_every_message_is_set() {
        for code in ALL {
            let serde_name = serde_json::to_value(code).expect("serialize");
            assert_eq!(serde_name, json!(code.as_str()));
            let (_, message) = code.defaults();
            assert!(!message.is_empty(), "{:?} has no message", code);
        }
    }

    #[test]
    fn unique_violations_map_to_codes() {
        let err = map_sql_state("23505", Some("users_email_key"));
        assert_eq!(err.code(), ErrorCode::EmailTaken);
        assert_eq!(err.status(), StatusCode::CONFLICT);

        let err = map_sql_state("23505", Some("users_username_key"));
        assert_eq!(err.code(), ErrorCode::UsernameTaken);

        let err = map_sql_state("23505", Some("products_user_name_key"));
        assert_eq!(err.code(), ErrorCode::NameTaken);
        assert_eq!(err.status(), StatusCode::CONFLICT);

        let err = map_sql_state("23505", Some("some_unknown_key"));
        assert_eq!(err.code(), ErrorCode::InvalidValue);
        assert_eq!(err.status(), StatusCode::CONFLICT);

        let err = map_sql_state("23505", None);
        assert_eq!(err.code(), ErrorCode::InvalidValue);
        assert_eq!(err.status(), StatusCode::CONFLICT);
    }

    #[test]
    fn check_violations_map_to_codes() {
        let err = map_sql_state("23514", Some("products_stock_nonneg"));
        assert_eq!(err.code(), ErrorCode::StockInsufficient);
        assert_eq!(err.status(), StatusCode::UNPROCESSABLE_ENTITY);

        let err = map_sql_state("23514", Some("products_price_nonneg"));
        assert_eq!(err.code(), ErrorCode::InvalidValue);
        assert_eq!(err.status(), StatusCode::UNPROCESSABLE_ENTITY);
    }

    #[test]
    fn foreign_key_violation_means_account_gone() {
        let err = map_sql_state("23503", Some("products_user_id_fkey"));
        assert_eq!(err.code(), ErrorCode::AccountGone);
        assert_eq!(err.status(), StatusCode::UNAUTHORIZED);
    }

    #[test]
    fn other_sql_states_are_internal() {
        let err = map_sql_state("42P01", None);
        assert_eq!(err.code(), ErrorCode::Internal);
        assert_eq!(err.status(), StatusCode::INTERNAL_SERVER_ERROR);
    }
}
