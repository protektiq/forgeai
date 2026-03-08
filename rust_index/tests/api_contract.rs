//! Contract tests for Rust index: GET /health, POST /index, GET /search.
//! Uses in-process router with MemoryStore (no external server).

use axum::body::Body;
use axum::http::{Request, StatusCode};
use rust_index::storage::MemoryStore;
use rust_index::{create_app, AppState};
use serde_json::json;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use tower::ServiceExt;

fn test_app() -> axum::Router {
    let store = Arc::new(MemoryStore::new());
    let ready = Arc::new(AtomicBool::new(true));
    let state = AppState { store, ready };
    create_app(state)
}

#[tokio::test]
async fn test_health_returns_200() {
    let app = test_app();
    let req = Request::builder()
        .uri("/health")
        .body(Body::empty())
        .unwrap();
    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_index_returns_204_and_search_finds_asset() {
    let app = test_app();
    let body = json!({
        "asset_id": "asset-1",
        "prompt": "a red balloon"
    });
    let req = Request::builder()
        .method("POST")
        .uri("/index")
        .header("Content-Type", "application/json")
        .body(Body::from(serde_json::to_vec(&body).unwrap()))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::NO_CONTENT);

    let search_req = Request::builder()
        .uri("/search?q=balloon")
        .body(Body::empty())
        .unwrap();
    let search_res = app.oneshot(search_req).await.unwrap();
    assert_eq!(search_res.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(search_res.into_body(), usize::MAX)
        .await
        .unwrap();
    let data: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let asset_ids = data.get("asset_ids").and_then(|v| v.as_array()).unwrap();
    assert!(asset_ids.iter().any(|v| v.as_str() == Some("asset-1")));
}

#[tokio::test]
async fn test_search_empty_q_returns_empty_array() {
    let app = test_app();
    let req = Request::builder()
        .uri("/search?q=")
        .body(Body::empty())
        .unwrap();
    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let data: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let asset_ids = data.get("asset_ids").and_then(|v| v.as_array()).unwrap();
    assert!(asset_ids.is_empty());
}
