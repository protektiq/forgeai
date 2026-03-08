//! Restart persistence test: index an asset, simulate restart (new store from same SQLite),
//! then verify search still returns the asset.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use rust_index::storage::{CompositeStore, IndexStore, SqliteStore};
use rust_index::{create_app, AppState};
use serde_json::json;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use tempfile::TempDir;
use tower::ServiceExt;

fn app_with_sqlite(path: &std::path::Path) -> axum::Router {
    let sqlite = SqliteStore::open(path).expect("open sqlite");
    let memory = sqlite.load_into_memory().expect("load into memory");
    let store: Arc<dyn IndexStore + Send + Sync> =
        Arc::new(CompositeStore::new(memory, sqlite));
    let ready = Arc::new(AtomicBool::new(true));
    let state = AppState { store, ready };
    create_app(state)
}

#[tokio::test]
async fn test_restart_persistence_search_returns_indexed_asset() {
    let dir = TempDir::new().unwrap();
    let db_path = dir.path().join("index.db");

    // First "run": create app, index one asset, search finds it
    {
        let app = app_with_sqlite(&db_path);
        let body = json!({
            "asset_id": "persisted-1",
            "prompt": "unique prompt for persistence test"
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
            .uri("/search?q=persistence")
            .body(Body::empty())
            .unwrap();
        let search_res = app.oneshot(search_req).await.unwrap();
        assert_eq!(search_res.status(), StatusCode::OK);
        let bytes = axum::body::to_bytes(search_res.into_body(), usize::MAX)
            .await
            .unwrap();
        let data: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        let asset_ids = data.get("asset_ids").and_then(|v| v.as_array()).unwrap();
        assert!(asset_ids.iter().any(|v| v.as_str() == Some("persisted-1")));
    }
    // First app and store are dropped here; SQLite file on disk has the data

    // Second "run": new SqliteStore from same path, load into memory, new app
    let app2 = app_with_sqlite(&db_path);
    let search_req2 = Request::builder()
        .uri("/search?q=persistence")
        .body(Body::empty())
        .unwrap();
    let search_res2 = app2.oneshot(search_req2).await.unwrap();
    assert_eq!(search_res2.status(), StatusCode::OK);
    let bytes2 = axum::body::to_bytes(search_res2.into_body(), usize::MAX)
        .await
        .unwrap();
    let data2: serde_json::Value = serde_json::from_slice(&bytes2).unwrap();
    let asset_ids2 = data2.get("asset_ids").and_then(|v| v.as_array()).unwrap();
    assert!(
        asset_ids2.iter().any(|v| v.as_str() == Some("persisted-1")),
        "after restart search must still return the indexed asset"
    );
}
