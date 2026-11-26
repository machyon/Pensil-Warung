//! Small response types for handlers.

use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;

/// 201 Created with a JSON body.
pub struct Created<T>(pub T);

impl<T: Serialize> IntoResponse for Created<T> {
    fn into_response(self) -> Response {
        (StatusCode::CREATED, Json(self.0)).into_response()
    }
}

/// 204 No Content.
pub struct NoContent;

impl IntoResponse for NoContent {
    fn into_response(self) -> Response {
        StatusCode::NO_CONTENT.into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn created_is_201() {
        let response = Created(serde_json::json!({ "id": 1 })).into_response();
        assert_eq!(response.status(), StatusCode::CREATED);
    }

    #[test]
    fn no_content_is_204() {
        assert_eq!(NoContent.into_response().status(), StatusCode::NO_CONTENT);
    }
}
