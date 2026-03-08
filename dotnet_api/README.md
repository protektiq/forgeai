# .NET API (public API gateway)

ASP.NET Core Web API that exposes the **versioned public API** entry point. It handles public authentication (API key), request validation, and response shaping; it proxies all business logic to the Rails app (Rails remains the system of record for workflows, jobs, and assets).

## Prerequisites

- **.NET SDK** 8.0
- **Rails app** running (e.g. http://localhost:3000) with API user configured

## Configuration

- **ApiKey** — Static key clients must send in `X-Api-Key` header. Set in `appsettings.json` or env `ASPNETCORE_API_KEY`. If empty, auth is skipped (dev only). Rotate by updating config/env.
- **Rails:BaseUrl** — Rails base URL (default `http://localhost:3000`).
- **Rails:InternalApiKey** — Optional. When set, C# sends this in `X-Internal-Api-Key` to Rails; set `RAILS_INTERNAL_API_KEY` in Rails to match.

Development defaults are in `appsettings.Development.json` (e.g. `ApiKey: "dev-api-key-change-in-production"`).

## Build and run

```bash
dotnet restore
dotnet build
dotnet run
```

Server listens on **http://localhost:5001** (see `Properties/launchSettings.json`).

## Ownership boundaries

- **.NET (public API gateway):** Public authentication (API key validation), request validation (required fields, lengths, formats), response shaping (consistent JSON and error format), and forwarding correlation id to Rails. It does **not** duplicate business logic.
- **Rails (source of truth):** Workflows, workflow runs, jobs, assets, and all business rules. The gateway proxies to Rails; Rails uses internal auth (`X-Internal-Api-Key`) and a single API user (or per-key user when that is added later).

## API key auth

All `/api/v1/*` routes require the `X-Api-Key` header when `ApiKey` (or `ASPNETCORE_API_KEY`) is set. Missing or invalid key returns `401` with body `{ "error": { "code": "unauthorized", "message": "Missing or invalid API key", "correlation_id": "..." } }`.

**Current model (Option A):** One static key in config/env. One key = one logical API user; Rails uses `API_USER_ID` (or first user) for all gateway traffic. Suitable for single-tenant or few keys.

**Future (Option B — per-key user):** To support multiple API keys each tied to a user (e.g. multi-tenant or billing), you could: (1) add an `ApiKey` model in Rails (e.g. `user_id`, hashed `key`) and have .NET validate keys via a Rails internal endpoint, with Rails accepting a header like `X-Api-User-Id` from the gateway to scope the request; or (2) store keys in .NET (config list or DB) and send `X-Api-User-Id` to Rails when the gateway is trusted. Rails would then need to resolve the API user from that header when the request is internal.

## Endpoints

All public API routes are under **`/api/v1/`**. The canonical contract is [docs/contracts/public-api-v1.yaml](../docs/contracts/public-api-v1.yaml) (OpenAPI).

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check (no auth). |
| POST | `/api/v1/generate` | Submit prompt; creates job in Rails. Returns `{ "job_id", "status": "queued" }` or `{ "workflow_run_id", "status": "queued" }`. |
| GET | `/api/v1/jobs/{id}` | Job status (for polling after create). Returns job object with `job_id`, `status`, `created_at`, `started_at`, `completed_at`, optional `error_message`, `asset_id`. |
| GET | `/api/v1/assets` | List assets. Optional query `?search=...` for semantic search. |
| GET | `/api/v1/search` | Semantic search. Query `?q=...` or `?search=...`; returns same array shape as list assets. |
| GET | `/api/v1/assets/{id}` | Get one asset by id (404 if not found). |

## Response formats

- **Errors:** All error responses use the standard shape: `{ "error": { "code", "message", "correlation_id" } }`. See [docs/contracts/error-response.md](../docs/contracts/error-response.md). Codes include `invalid_request`, `unauthorized`, `not_found`, `bad_gateway`, etc.
- **Success:** Success bodies are proxied from Rails and documented in the OpenAPI spec (generate response, job object, asset object / array).

## Example (curl)

Set `KEY` to your configured API key (e.g. `dev-api-key-change-in-production` in dev).

**Generate:**

```bash
curl -X POST http://localhost:5001/api/v1/generate \
  -H "X-Api-Key: $KEY" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"a red cube"}'
```

Expected: `201` with `{ "job_id": 1, "status": "queued" }`.

**Job status:**

```bash
curl "http://localhost:5001/api/v1/jobs/1" -H "X-Api-Key: $KEY"
```

**List assets / search:**

```bash
curl "http://localhost:5001/api/v1/assets?search=cube" -H "X-Api-Key: $KEY"
curl "http://localhost:5001/api/v1/search?q=cube" -H "X-Api-Key: $KEY"
```

**Get asset by id:**

```bash
curl "http://localhost:5001/api/v1/assets/1" -H "X-Api-Key: $KEY"
```

**No/wrong API key:** `401` with `{ "error": { "code": "unauthorized", "message": "Missing or invalid API key", "correlation_id": "..." } }`.

## Test instructions

From repo root:

```bash
dotnet test dotnet_api.Tests/dotnet_api.Tests.csproj
```

See [docs/testing.md](../docs/testing.md) for contract and malformed input tests.

## Rails setup for C# API

- **API_USER_ID** — User id for API-created jobs and assets (optional; if unset, first user is used).
- **RAILS_INTERNAL_API_KEY** — If set, Rails requires `X-Internal-Api-Key` header on `/api/v1/*` (set same value in C# `Rails:InternalApiKey`).
- **HOST_FOR_BLOB_URLS** — Optional. Base URL for `download_url` in asset JSON (e.g. `http://localhost:3000`).
