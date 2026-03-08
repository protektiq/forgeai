use std::net::SocketAddr;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use rust_index::{create_app, storage::CompositeStore, storage::IndexStore, storage::SqliteStore, AppState};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::from_default_env().add_directive("rust_index=info".parse().unwrap()))
        .with(tracing_subscriber::fmt::layer().json())
        .init();

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(3132);
    let addr: SocketAddr = ([0, 0, 0, 0], port).into();

    let index_data_path = std::env::var("INDEX_DATA_PATH").unwrap_or_else(|_| "./data/index.db".into());

    let ready = Arc::new(AtomicBool::new(false));
    let sqlite = SqliteStore::open(&index_data_path).expect("open index database");
    let memory = sqlite.load_into_memory().expect("load index into memory");
    let store: Arc<dyn IndexStore + Send + Sync> =
        Arc::new(CompositeStore::new(memory, sqlite));
    ready.store(true, std::sync::atomic::Ordering::Release);

    let app = create_app(AppState { store, ready });

    let listener = tokio::net::TcpListener::bind(addr).await.expect("bind");
    tracing::info!(service = "rust_index", message = %format!("listening on http://{}", addr));
    axum::serve(listener, app).await.expect("serve");
}
