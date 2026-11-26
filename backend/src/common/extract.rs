//! Extractor wrappers whose rejections become [`AppError`] instead of
//! Axum's plain-text errors.

use axum::Json;
use axum::extract::rejection::{JsonRejection, PathRejection, QueryRejection};
use axum::extract::{FromRequest, FromRequestParts, Path, Query, Request};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::json;

use crate::error::{AppError, ErrorCode};

/// JSON body extractor and response. Failures are `invalid_body` (400), or
/// `payload_too_large` (413) when the body exceeds the body limit.
/// The reason comes from serde and never echoes the request body.
pub struct ApiJson<T>(pub T);

impl<S, T> FromRequest<S> for ApiJson<T>
where
    S: Send + Sync,
    T: DeserializeOwned,
{
    type Rejection = AppError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        match Json::<T>::from_request(req, state).await {
            Ok(Json(value)) => Ok(Self(value)),
            Err(rejection) => Err(json_error(rejection)),
        }
    }
}

fn json_error(rejection: JsonRejection) -> AppError {
    if rejection.status() == StatusCode::PAYLOAD_TOO_LARGE {
        return AppError::new(ErrorCode::PayloadTooLarge);
    }
    AppError::new(ErrorCode::InvalidBody).with_details(json!({ "reason": rejection.body_text() }))
}

impl<T: Serialize> IntoResponse for ApiJson<T> {
    fn into_response(self) -> Response {
        Json(self.0).into_response()
    }
}

/// Query-string extractor. Failures are `invalid_query` (400).
pub struct ApiQuery<T>(pub T);

impl<S, T> FromRequestParts<S> for ApiQuery<T>
where
    S: Send + Sync,
    T: DeserializeOwned,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        match Query::<T>::from_request_parts(parts, state).await {
            Ok(Query(value)) => Ok(Self(value)),
            Err(rejection) => Err(query_error(rejection)),
        }
    }
}

fn query_error(rejection: QueryRejection) -> AppError {
    AppError::new(ErrorCode::InvalidQuery).with_details(json!({ "reason": rejection.body_text() }))
}

/// Path-parameter extractor. Failures are `invalid_path` (400).
pub struct ApiPath<T>(pub T);

impl<S, T> FromRequestParts<S> for ApiPath<T>
where
    S: Send + Sync,
    T: DeserializeOwned + Send,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        match Path::<T>::from_request_parts(parts, state).await {
            Ok(Path(value)) => Ok(Self(value)),
            Err(rejection) => Err(path_error(rejection)),
        }
    }
}

fn path_error(rejection: PathRejection) -> AppError {
    match rejection {
        // A route/handler mismatch is a server bug, not a client mistake.
        PathRejection::MissingPathParams(err) => {
            tracing::error!(error = %err, "path extractor used on a route without parameters");
            AppError::internal()
        }
        other => AppError::new(ErrorCode::InvalidPath)
            .with_details(json!({ "reason": other.body_text() })),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::Router;
    use axum::body::Body;
    use axum::http::{Request, header};
    use axum::routing::{get, post};
    use http_body_util::BodyExt;
    use serde::Deserialize;
    use tower::ServiceExt;

    #[derive(Deserialize, Serialize)]
    struct Item {
        name: String,
    }

    #[derive(Deserialize)]
    struct Paging {
        #[allow(dead_code)]
        limit: u32,
    }

    fn app() -> Router {
        Router::new()
            .route(
                "/json",
                post(|ApiJson(item): ApiJson<Item>| async move { ApiJson(item) }),
            )
            .route(
                "/query",
                get(|ApiQuery(_): ApiQuery<Paging>| async { "ok" }),
            )
            .route("/path/{id}", get(|ApiPath(_): ApiPath<i64>| async { "ok" }))
    }

    async fn call(req: Request<Body>) -> (StatusCode, serde_json::Value) {
        let response = app().oneshot(req).await.expect("response");
        let status = response.status();
        let bytes = response
            .into_body()
            .collect()
            .await
            .expect("body")
            .to_bytes();
        let json = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
        (status, json)
    }

    fn json_post(body: &str) -> Request<Body> {
        Request::post("/json")
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(body.to_owned()))
            .expect("request")
    }

    #[tokio::test]
    async fn valid_json_passes_through() {
        let (status, json) = call(json_post(r#"{"name":"nasi"}"#)).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(json["name"], "nasi");
    }

    #[tokio::test]
    async fn malformed_json_is_invalid_body() {
        let (status, json) = call(json_post("{not json")).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(json["error"]["code"], "invalid_body");
        assert!(json["error"]["details"]["reason"].is_string());
    }

    #[tokio::test]
    async fn wrong_shape_is_invalid_body_without_echoing_body() {
        let body = r#"{"name":12345678,"secret":"hunter2"}"#;
        let (status, json) = call(json_post(body)).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(json["error"]["code"], "invalid_body");
        assert!(!json.to_string().contains("hunter2"));
        assert!(!json.to_string().contains(body));
    }

    #[tokio::test]
    async fn missing_content_type_is_invalid_body() {
        let req = Request::post("/json")
            .body(Body::from(r#"{"name":"x"}"#))
            .expect("request");
        let (status, json) = call(req).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(json["error"]["code"], "invalid_body");
    }

    #[tokio::test]
    async fn oversized_body_is_payload_too_large() {
        let app = app().layer(axum::extract::DefaultBodyLimit::max(8));
        let response = app
            .oneshot(json_post(r#"{"name":"much too long for the limit"}"#))
            .await
            .expect("response");
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
        let bytes = response
            .into_body()
            .collect()
            .await
            .expect("body")
            .to_bytes();
        let json: serde_json::Value = serde_json::from_slice(&bytes).expect("json");
        assert_eq!(json["error"]["code"], "payload_too_large");
    }

    #[tokio::test]
    async fn bad_query_is_invalid_query() {
        let req = Request::get("/query?limit=abc")
            .body(Body::empty())
            .expect("request");
        let (status, json) = call(req).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(json["error"]["code"], "invalid_query");
    }

    #[tokio::test]
    async fn bad_path_is_invalid_path() {
        let req = Request::get("/path/abc")
            .body(Body::empty())
            .expect("request");
        let (status, json) = call(req).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(json["error"]["code"], "invalid_path");
    }
}
