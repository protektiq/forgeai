# Rust index

HTTP service for full-text-style search over asset prompts, tags, and metadata. Used by the Rails app to index assets after creation and to run search from the asset library.

## Prerequisites

- **Rust** toolchain (rustc, cargo). Install from https://rustup.rs/

## Build

```bash
cargo build
```

Release build (recommended for running the server):

```bash
cargo build --release
```

## Run

```bash
cargo run
```

Or, after a release build:

```bash
./target/release/rust_index
```

**Environment:**

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT`   | `3132`  | Port to bind. Use a different value to avoid clashes with Rails (3000), Python gen (5000), or C++ media (8080). |
| `INDEX_DATA_PATH` | `./data/index.db` | Path to SQLite database file. The index is persisted here so search survives restarts. Directory is created if missing. |

**Persistence:** The index is stored in SQLite (single file). On startup the service loads all previously indexed assets from disk and serves search from memory; new index requests are written to both memory and SQLite. This keeps search fast while making the index durable. An optional future upgrade is Tantivy for full-text ranking; the storage layer is abstracted so the backend can be swapped.

The server listens on `0.0.0.0:PORT` (all interfaces). Example: with default port, base URL is `http://localhost:3132`.

## API

### POST /index

Index or update one asset. Request body (JSON):

- `asset_id` (string, required) — unique id (e.g. Rails asset id).
- `prompt` (string, required) — searchable prompt text.
- `metadata` (object, optional) — arbitrary JSON; flattened into searchable text.
- `tags` (array of strings, optional) — searchable tags.
- `embedding` (array of numbers, optional) — reserved for future vector search; stored but not used for search in this MVP.

Response: `204 No Content` on success. `400 Bad Request` if `asset_id` or `prompt` is missing or invalid.

**Example:**

```bash
curl -X POST http://localhost:3132/index \
  -H "Content-Type: application/json" \
  -d '{"asset_id":"42","prompt":"a red dragon","metadata":{"generator":{"seed":1,"model":"sd"}},"tags":[]}'
```

### GET /search?q=...

Search for assets whose combined prompt, metadata, and tags contain the query string (case-insensitive substring match).

- `q` (query parameter) — search string. If empty, returns an empty list.

Response: JSON `{ "asset_ids": ["id1", "id2", ...] }`.

**Example:**

```bash
curl "http://localhost:3132/search?q=dragon"
```

### GET /health

Liveness. Returns `200 OK` with no body.

**Example:**

```bash
curl http://localhost:3132/health
```

### GET /ready

Readiness. Returns `200 OK` with `{ "ready": true }` once the index has been loaded from disk at startup. Before that (e.g. during startup), returns `503 Service Unavailable` with `{ "ready": false }`. Use this to ensure the service is ready before sending search or index traffic.

**Example:**

```bash
curl http://localhost:3132/ready
```

### POST /rebuild

Maintenance endpoint: clears the entire index (in-memory and persisted). Returns `204 No Content` on success. After a rebuild, Rails (or another client) can re-send all assets via `POST /index` to repopulate the index. Idempotent (empty index after call).

**Example:**

```bash
curl -X POST http://localhost:3132/rebuild
```

## Test instructions

From `rust_index/`:

```bash
cargo test
```

Includes API contract and persistence tests. See [docs/testing.md](../docs/testing.md).

## First run

The first `cargo build` or `cargo run` may download and compile dependencies and can take a bit longer. Subsequent builds are incremental.

## Integration

Set `INDEX_SERVICE_URL` in the Rails app (e.g. `http://localhost:3132`). After each asset creation, Rails POSTs to `/index`. The asset library search box sends GET `/search?q=...` and filters the displayed assets by the returned `asset_ids`. The index is durable: it is stored in SQLite and survives restarts, so Rails can rely on the Rust service as the source of truth for search when `INDEX_SERVICE_URL` is set. Before sending traffic, you can ensure the index service is ready by checking GET `/ready` (returns 200 when loaded). For repair or full reindexing, call POST `/rebuild` then re-POST all assets to `/index`.
