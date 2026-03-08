//! Index storage abstraction: in-memory and SQLite-backed implementations.
//! Handlers use the trait only; persistence is an implementation detail.

use rusqlite::Connection;
use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex, RwLock};

/// Errors from index store operations.
#[derive(Debug)]
pub enum StoreError {
    Sqlite(rusqlite::Error),
    Io(std::io::Error),
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StoreError::Sqlite(e) => write!(f, "sqlite: {}", e),
            StoreError::Io(e) => write!(f, "io: {}", e),
        }
    }
}

impl std::error::Error for StoreError {}

impl From<rusqlite::Error> for StoreError {
    fn from(e: rusqlite::Error) -> Self {
        StoreError::Sqlite(e)
    }
}

impl From<std::io::Error> for StoreError {
    fn from(e: std::io::Error) -> Self {
        StoreError::Io(e)
    }
}

/// Abstraction for index storage. Implementations may be in-memory only or persistent.
pub trait IndexStore: Send + Sync {
    /// Insert or replace an entry for `asset_id`.
    fn insert(
        &self,
        asset_id: &str,
        searchable: &str,
        embedding: Option<&[f64]>,
    ) -> Result<(), StoreError>;

    /// Return asset_ids whose searchable text contains `needle` (case-insensitive substring).
    fn search(&self, needle: &str) -> Result<Vec<String>, StoreError>;

    /// Remove all entries (for rebuild). Idempotent.
    fn clear(&self) -> Result<(), StoreError>;

    /// Number of entries in the index (for metrics/readiness).
    fn len(&self) -> usize;
}

/// In-memory store: fast, no persistence. Used after loading from SQLite at startup.
#[derive(Default)]
pub struct MemoryStore {
    inner: RwLock<HashMap<String, (String, Option<Vec<f64>>)>>,
}

impl MemoryStore {
    pub fn new() -> Self {
        Self {
            inner: RwLock::new(HashMap::new()),
        }
    }
}

impl IndexStore for MemoryStore {
    fn insert(
        &self,
        asset_id: &str,
        searchable: &str,
        embedding: Option<&[f64]>,
    ) -> Result<(), StoreError> {
        let emb = embedding.map(|v| v.to_vec());
        self.inner
            .write()
            .map_err(|_| StoreError::Sqlite(rusqlite::Error::InvalidParameterName("poisoned".into())))?
            .insert(asset_id.to_string(), (searchable.to_string(), emb));
        Ok(())
    }

    fn search(&self, needle: &str) -> Result<Vec<String>, StoreError> {
        let needle = needle.to_lowercase();
        let guard = self
            .inner
            .read()
            .map_err(|_| StoreError::Sqlite(rusqlite::Error::InvalidParameterName("poisoned".into())))?;
        let asset_ids: Vec<String> = guard
            .iter()
            .filter(|(_, (searchable, _))| searchable.to_lowercase().contains(&needle))
            .map(|(id, _)| id.clone())
            .collect();
        Ok(asset_ids)
    }

    fn clear(&self) -> Result<(), StoreError> {
        self.inner
            .write()
            .map_err(|_| StoreError::Sqlite(rusqlite::Error::InvalidParameterName("poisoned".into())))?
            .clear();
        Ok(())
    }

    fn len(&self) -> usize {
        self.inner
            .read()
            .map(|g| g.len())
            .unwrap_or(0)
    }
}

const TABLE_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS index_entries (
    asset_id TEXT PRIMARY KEY NOT NULL,
    searchable TEXT NOT NULL,
    embedding TEXT
)"#;

/// SQLite-backed store: persists to disk. Used to load at startup and to persist on insert/clear.
pub struct SqliteStore {
    #[allow(dead_code)]
    path: std::path::PathBuf,
    conn: Mutex<Connection>,
}

impl SqliteStore {
    /// Open or create the database and ensure the table exists.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StoreError> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            if !parent.exists() {
                std::fs::create_dir_all(parent)?;
            }
        }
        let conn = Connection::open(&path)?;
        conn.execute_batch(TABLE_SCHEMA)?;
        Ok(Self { path, conn: Mutex::new(conn) })
    }

    /// Load all rows from SQLite into a MemoryStore. Used at startup.
    pub fn load_into_memory(&self) -> Result<MemoryStore, StoreError> {
        let store = MemoryStore::new();
        let conn = self.conn.lock().map_err(|_| {
            StoreError::Sqlite(rusqlite::Error::InvalidParameterName("poisoned".into()))
        })?;
        let mut stmt = conn.prepare("SELECT asset_id, searchable, embedding FROM index_entries")?;
        let rows = stmt.query_map([], |row| {
            let asset_id: String = row.get(0)?;
            let searchable: String = row.get(1)?;
            let embedding: Option<String> = row.get(2)?;
            let embedding = embedding
                .and_then(|s| serde_json::from_str::<Vec<f64>>(&s).ok())
                .filter(|v| !v.is_empty());
            Ok((asset_id, searchable, embedding))
        })?;
        for row in rows {
            let (asset_id, searchable, embedding) = row?;
            store.insert(&asset_id, &searchable, embedding.as_deref())?;
        }
        Ok(store)
    }
}

impl IndexStore for SqliteStore {
    fn insert(
        &self,
        asset_id: &str,
        searchable: &str,
        embedding: Option<&[f64]>,
    ) -> Result<(), StoreError> {
        let embedding_json = embedding.and_then(|v| serde_json::to_string(v).ok());
        let conn = self.conn.lock().map_err(|_| {
            StoreError::Sqlite(rusqlite::Error::InvalidParameterName("poisoned".into()))
        })?;
        conn.execute(
            "INSERT OR REPLACE INTO index_entries (asset_id, searchable, embedding) VALUES (?1, ?2, ?3)",
            rusqlite::params![asset_id, searchable, embedding_json],
        )?;
        Ok(())
    }

    fn search(&self, needle: &str) -> Result<Vec<String>, StoreError> {
        let needle = format!("%{}%", needle.to_lowercase());
        let conn = self.conn.lock().map_err(|_| {
            StoreError::Sqlite(rusqlite::Error::InvalidParameterName("poisoned".into()))
        })?;
        let mut stmt = conn.prepare(
            "SELECT asset_id FROM index_entries WHERE LOWER(searchable) LIKE ?1 ESCAPE '\\'",
        )?;
        let rows = stmt.query_map([&needle], |row| row.get::<_, String>(0))?;
        let asset_ids: Result<Vec<_>, _> = rows.collect();
        Ok(asset_ids?)
    }

    fn clear(&self) -> Result<(), StoreError> {
        let conn = self.conn.lock().map_err(|_| {
            StoreError::Sqlite(rusqlite::Error::InvalidParameterName("poisoned".into()))
        })?;
        conn.execute("DELETE FROM index_entries", [])?;
        Ok(())
    }

    fn len(&self) -> usize {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(_) => return 0,
        };
        conn.query_row("SELECT COUNT(*) FROM index_entries", [], |row| row.get::<_, i64>(0))
            .unwrap_or(0) as usize
    }
}

/// Composite store: in-memory is the source of truth for search; SQLite is written on insert/clear
/// so we can rehydrate on next startup. Rebuild clears both.
pub struct CompositeStore {
    memory: Arc<MemoryStore>,
    sqlite: Arc<SqliteStore>,
}

impl CompositeStore {
    pub fn new(memory: MemoryStore, sqlite: SqliteStore) -> Self {
        Self {
            memory: Arc::new(memory),
            sqlite: Arc::new(sqlite),
        }
    }

    #[allow(dead_code)]
    pub fn memory(&self) -> &MemoryStore {
        &self.memory
    }
}

impl IndexStore for CompositeStore {
    fn insert(
        &self,
        asset_id: &str,
        searchable: &str,
        embedding: Option<&[f64]>,
    ) -> Result<(), StoreError> {
        self.memory.insert(asset_id, searchable, embedding)?;
        self.sqlite.insert(asset_id, searchable, embedding)?;
        Ok(())
    }

    fn search(&self, needle: &str) -> Result<Vec<String>, StoreError> {
        self.memory.search(needle)
    }

    fn clear(&self) -> Result<(), StoreError> {
        self.memory.clear()?;
        self.sqlite.clear()?;
        Ok(())
    }

    fn len(&self) -> usize {
        self.memory.len()
    }
}
