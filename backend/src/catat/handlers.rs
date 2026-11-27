//! `POST /catat`: one Simpan as one atomic batch.

use axum::Json;
use axum::Router;
use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::post;
use uuid::Uuid;

use super::dto::{CatatRequest, CatatResponse, Op, lines_invalid};
use super::exec::{execute, find_by_client_uuid, product_stocks};
use super::{load_products, plan::plan};
use crate::auth::extractor::AuthUser;
use crate::auth::perms::Perm;
use crate::common::extract::ApiJson;
use crate::error::AppError;
use crate::products::photo;
use crate::state::AppState;
use tokio_postgres::GenericClient;

pub fn routes() -> Router<AppState> {
    Router::new().route("/catat", post(catat))
}

/// The stored transaction for a retry, with its products' current stock.
async fn replay(
    client: &impl GenericClient,
    user_id: Uuid,
    client_uuid: Uuid,
) -> Result<Option<CatatResponse>, AppError> {
    let Some(transaction) = find_by_client_uuid(client, user_id, client_uuid).await? else {
        return Ok(None);
    };
    let ids: Vec<i64> = transaction
        .items
        .iter()
        .filter_map(|i| i.product_id)
        .collect();
    Ok(Some(CatatResponse {
        products_changed: product_stocks(client, user_id, &ids).await?,
        products_deleted: Vec::new(),
        transaction: Some(transaction),
    }))
}

async fn catat(
    State(state): State<AppState>,
    user: AuthUser,
    ApiJson(req): ApiJson<CatatRequest>,
) -> Result<(StatusCode, Json<CatatResponse>), AppError> {
    state.perms.require(&user, Perm::TransactionCreate)?;
    let batch = req.validate()?;
    if batch.ops.iter().any(|op| !matches!(op, Op::Sale { .. })) {
        state.perms.require(&user, Perm::ProductManage)?;
    }

    let mut client = state.pool.get().await?;
    if let Some(r) = replay(&**client, user.id, batch.client_uuid).await? {
        return Ok((StatusCode::OK, Json(r)));
    }

    let tx = client.transaction().await?;
    let snapshot = load_products(&*tx, user.id).await?;
    let plan = match plan(&batch.ops, snapshot) {
        Ok(plan) => plan,
        Err(lines) => {
            drop(tx);
            // A concurrent duplicate may have used up the stock this retry needs.
            if let Some(r) = replay(&**client, user.id, batch.client_uuid).await? {
                return Ok((StatusCode::OK, Json(r)));
            }
            return Err(lines_invalid(&lines));
        }
    };
    let Some((response, photo_keys)) = execute(&*tx, user.id, &batch, plan).await? else {
        drop(tx);
        // Lost the race on client_uuid: the winner's transaction is the answer.
        let r = replay(&**client, user.id, batch.client_uuid)
            .await?
            .ok_or_else(AppError::internal)?;
        return Ok((StatusCode::OK, Json(r)));
    };
    tx.commit().await?;
    for key in photo_keys {
        photo::delete_object(&state.storage, Some(key)).await;
    }
    Ok((StatusCode::CREATED, Json(response)))
}
