# Rust index

In-memory search index for assets. The Rails worker POSTs new assets to `/index`; the asset library uses GET `/search?q=...` to filter by prompt/metadata/tags.

## Port

Default: **3132**. Override with env **PORT**.

## Endpoints

### GET /health

Health check.

- **Response**: **200** OK (no body in implementation; safe to treat as 200).

### POST /index

Index an asset for later search.

**Request**

- **Content-Type**: `application/json`
- **Body**: `{ "asset_id": "string", "prompt": "string", "metadata?", "tags?", "embedding?" }`
  - `asset_id`: Required, non-empty, max 256 characters.
  - `prompt`: Required, non-empty, max 10000 characters.
  - `metadata`: Optional JSON value (merged into searchable text).
  - `tags`: Optional array of strings (merged into searchable text).
  - `embedding`: Optional array of f64 (reserved for future vector search).

**Response**

- **204** No Content — Success.
- **400** — Validation error (e.g. missing or empty `asset_id`/`prompt`, or length exceeded). Body: plain text error message.

### GET /search

Search indexed assets by query string.

**Request**

- **Query**: `q=<string>` — Search term (trimmed; empty returns no results).

**Response**

- **200** `{ "asset_ids": [ "<id1>", "<id2>", ... ] }`
  - Matching is case-insensitive substring over the combined searchable text (prompt + metadata string + tags).
  - Empty `q` returns `{ "asset_ids": [] }`.

## Optional headers

- **X-Correlation-Id** / **X-Request-Id**: Logged for request tracing.

## CORS

CORS is enabled (any origin/methods/headers) for browser clients.
