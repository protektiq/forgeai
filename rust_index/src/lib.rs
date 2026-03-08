//! Library for rust_index service: app router and storage.
//! Used by the binary and by integration tests.

pub mod storage;

use axum::{
    extract::{Extension, Query, State},
    http::StatusCode,
    middleware as axum_middleware,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};

use storage::IndexStore;

const MAX_ASSET_ID_LEN: usize = 256;
const MAX_PROMPT_LEN: usize = 10_000;

/// Correlation id from X-Correlation-Id or X-Request-Id (set by middleware).
#[derive(Clone)]
struct CorrelationId(pub String);

/// Standard error response shape (see docs/contracts/error-response.md).
#[derive(Serialize)]
struct ErrorPart {
    code: String,
    message: String,
    #[serde(rename = "correlation_id")]
    correlation_id: String,
}

#[derive(Serialize)]
struct ApiErrorPayload {
    error: ErrorPart,
}

impl ApiErrorPayload {
    fn new(code: &str, message: impl Into<String>, correlation_id: String) -> Self {
        Self {
            error: ErrorPart {
                code: code.to_string(),
                message: message.into(),
                correlation_id,
            },
        }
    }
}

type ApiErrorResponse = (StatusCode, Json<ApiErrorPayload>);

/// Application state shared by handlers.
#[derive(Clone)]
pub struct AppState {
    pub store: Arc<dyn IndexStore + Send + Sync>,
    pub ready: Arc<AtomicBool>,
}

#[derive(Clone)]
struct IndexEntry {
    searchable: String,
    embedding: Option<Vec<f64>>,
}

#[derive(Debug, Deserialize)]
struct IndexRequest {
    asset_id: String,
    prompt: String,
    #[serde(default)]
    metadata: Option<serde_json::Value>,
    #[serde(default)]
    tags: Option<Vec<String>>,
    #[serde(default)]
    embedding: Option<Vec<f64>>,
}

#[derive(Debug, Serialize)]
struct SearchResponse {
    asset_ids: Vec<String>,
}

fn build_searchable(prompt: &str, metadata: Option<&serde_json::Value>, tags: Option<&[String]>) -> String {
    let mut parts = vec![prompt.to_string()];
    if let Some(m) = metadata {
        if let Ok(s) = serde_json::to_string(m) {
            parts.push(s);
        }
    }
    if let Some(t) = tags {
        parts.push(t.join(" "));
    }
    parts.join(" ").to_lowercase()
}

fn validate_index_request(body: &IndexRequest) -> Result<(), (StatusCode, &'static str)> {
    let aid = body.asset_id.trim();
    if aid.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "asset_id is required and must be non-empty"));
    }
    if aid.len() > MAX_ASSET_ID_LEN {
        return Err((
            StatusCode::BAD_REQUEST,
            "asset_id exceeds maximum length",
        ));
    }
    let prompt = body.prompt.trim();
    if prompt.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "prompt is required and must be non-empty"));
    }
    if prompt.len() > MAX_PROMPT_LEN {
        return Err((
            StatusCode::BAD_REQUEST,
            "prompt exceeds maximum length",
        ));
    }
    Ok(())
}

async fn index_handler(
    State(state): State<AppState>,
    Extension(corr_id): Extension<CorrelationId>,
    Json(body): Json<IndexRequest>,
) -> Result<StatusCode, ApiErrorResponse> {
    if let Err((code, msg)) = validate_index_request(&body) {
        let payload = ApiErrorPayload::new("invalid_request", msg, corr_id.0.clone());
        return Err((code, Json(payload)));
    }
    let asset_id = body.asset_id.trim().to_string();
    let searchable = build_searchable(
        body.prompt.trim(),
        body.metadata.as_ref(),
        body.tags.as_deref(),
    );
    let entry = IndexEntry {
        searchable,
        embedding: body.embedding,
    };
    if let Err(e) = state.store.insert(asset_id.as_str(), &entry.searchable, entry.embedding.as_deref()) {
        let payload = ApiErrorPayload::new(
            "index_error",
            format!("Failed to persist index: {}", e),
            corr_id.0.clone(),
        );
        return Err((StatusCode::INTERNAL_SERVER_ERROR, Json(payload)));
    }
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
struct SearchQuery {
    q: String,
}

async fn search_handler(
    State(state): State<AppState>,
    Query(query): Query<SearchQuery>,
) -> Result<Json<SearchResponse>, (StatusCode, String)> {
    let q = query.q.trim();
    if q.is_empty() {
        return Ok(Json(SearchResponse {
            asset_ids: vec![],
        }));
    }
    let needle = q.to_lowercase();
    let asset_ids = state.store.search(&needle).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Search failed: {}", e),
        )
    })?;
    Ok(Json(SearchResponse { asset_ids }))
}

async fn health_handler() -> StatusCode {
    StatusCode::OK
}

#[derive(Serialize)]
struct ReadyResponse {
    ready: bool,
}

async fn ready_handler(State(state): State<AppState>) -> (StatusCode, Json<ReadyResponse>) {
    let ready = state.ready.load(Ordering::Acquire);
    if ready {
        (StatusCode::OK, Json(ReadyResponse { ready: true }))
    } else {
        (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ReadyResponse { ready: false }),
        )
    }
}

async fn rebuild_handler(
    State(state): State<AppState>,
    Extension(corr_id): Extension<CorrelationId>,
) -> Result<StatusCode, ApiErrorResponse> {
    if let Err(e) = state.store.clear() {
        let payload = ApiErrorPayload::new(
            "rebuild_error",
            format!("Failed to clear index: {}", e),
            corr_id.0.clone(),
        );
        return Err((StatusCode::INTERNAL_SERVER_ERROR, Json(payload)));
    }
    Ok(StatusCode::NO_CONTENT)
}

async fn log_correlation_id(
    mut req: axum::http::Request<axum::body::Body>,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let id = req
        .headers()
        .get("X-Correlation-Id")
        .or_else(|| req.headers().get("X-Request-Id"))
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(String::new);
    tracing::info!(
        correlation_id = %id,
        path = %req.uri().path(),
        "request"
    );
    req.extensions_mut().insert(CorrelationId(id));
    next.run(req).await
}

/// Build the application router for the given state.
/// Used by the binary and by integration tests.
pub fn create_app(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/index", post(index_handler))
        .route("/search", get(search_handler))
        .route("/health", get(health_handler))
        .route("/ready", get(ready_handler))
        .route("/rebuild", post(rebuild_handler))
        .layer(axum_middleware::from_fn(log_correlation_id))
        .layer(cors)
        .with_state(state)
}
