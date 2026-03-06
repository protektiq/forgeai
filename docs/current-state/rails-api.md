# Rails API (v1)

Rails is the system of record. The API under `/api/v1` is the internal JSON API used by the .NET proxy and by direct API clients.

## Port

Default: **3000** (`rails s`). Override with `rails s -p <port>`.

## Authentication

- When `RAILS_INTERNAL_API_KEY` is set, all requests to `/api/v1/*` must include header:
  - `X-Internal-Api-Key`: value matching `RAILS_INTERNAL_API_KEY`
- Unauthorized requests receive **401** with no body.
- All actions are scoped to a single **API user**:
  - If `API_USER_ID` is set, that user is used.
  - Otherwise (e.g. development), the first user is used.
- If no API user is configured or found, responses are **503** with `{ "error": "API user not configured or not found" }`.

## Endpoints

| Method | Path | Request | Response |
|--------|------|---------|----------|
| POST | /api/v1/generate | JSON body: `{ "prompt": "string" }`. Prompt required, 1–10000 characters. | **201** `{ "job_id": <id>, "status": "queued" }` or **422** `{ "error": "..." }` |
| GET | /api/v1/jobs/:id | — | **200** `{ "job_id", "status", "created_at", "started_at", "completed_at", "error_message?" (if failed), "asset_id?" (if completed) }` or **404** `{ "error": "Job not found" }` |
| GET | /api/v1/assets | Optional query: `?search=<query>`. When `INDEX_SERVICE_URL` is set and `search` is present, results are filtered via Rust index GET /search?q=... | **200** Array of asset objects (see below) |
| GET | /api/v1/assets/:id | — | **200** Single asset object or **404** (no body) |

### Asset object (list and show)

```json
{
  "id": 123,
  "created_at": "2025-03-05T12:00:00.000Z",
  "prompt": "the prompt used for generation",
  "metadata": {},
  "download_url": "/rails/active_storage/..."
}
```

- `metadata`: Optional object; may include `generator: { "seed", "model" }`.
- `download_url`: Rails blob path; if `HOST_FOR_BLOB_URLS` is set, this is absolute (e.g. `https://app.example.com/rails/active_storage/...`).

## Other Rails routes (out of scope for API contract)

- **Active Storage**: mounted at `/rails/active_storage`.
- **Devise**: sign in / sign up / sign out (HTML).
- **Dashboard**: GET/POST `/dashboard` (HTML; POST creates a job with `generation_job[prompt]`).
- **Job details**: GET `/jobs/:id` (HTML).
- **Assets**: GET `/assets`, GET `/assets/:id`, GET `/assets/:id/download` (HTML).

## Rate limiting

Prompt creation (`POST /api/v1/generate` and `POST /dashboard`) is throttled per IP. Default: 30 requests per minute. Configure with `RACK_ATTACK_THROTTLE_LIMIT`. Throttled requests receive **429** with `{ "error": "Rate limit exceeded" }`.
