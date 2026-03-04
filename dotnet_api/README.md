# .NET API (external API surface)

ASP.NET Core Web API that exposes a second official API entry point with static API-key auth. It proxies generate and assets to the Rails app (Rails remains system of record).

## Prerequisites

- **.NET SDK** 8.0
- **Rails app** running (e.g. http://localhost:3000) with API user configured

## Configuration

- **ApiKey** — Static key clients must send in `X-Api-Key` header. Set in `appsettings.json` or env `ASPNETCORE_API_KEY`. If empty, auth is skipped (dev only).
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

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check (no auth). |
| POST | `/api/generate` | Submit prompt; creates job in Rails, returns `{ "job_id", "status": "queued" }`. |
| GET | `/api/assets` | List assets (optional query `?search=...`). |
| GET | `/api/assets/{id}` | Get one asset by id (404 if not found). |

All `/api/*` routes require `X-Api-Key` header (unless `ApiKey` is not set).

## Example (curl)

Set `KEY` to your configured API key (e.g. `dev-api-key-change-in-production` in dev).

**Generate:**

```bash
curl -X POST http://localhost:5001/api/generate \
  -H "X-Api-Key: $KEY" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"a red cube"}'
```

Expected: `201` with `{ "job_id": 1, "status": "queued" }`.

**List assets:**

```bash
curl "http://localhost:5001/api/assets?search=cube" -H "X-Api-Key: $KEY"
```

**Get asset by id:**

```bash
curl "http://localhost:5001/api/assets/1" -H "X-Api-Key: $KEY"
```

**No/wrong API key:** `401` with `{ "error": "Missing or invalid API key" }`.

## Rails setup for C# API

- **API_USER_ID** — User id for API-created jobs and assets (optional; if unset, first user is used).
- **RAILS_INTERNAL_API_KEY** — If set, Rails requires `X-Internal-Api-Key` header on `/api/v1/*` (set same value in C# `Rails:InternalApiKey`).
- **HOST_FOR_BLOB_URLS** — Optional. Base URL for `download_url` in asset JSON (e.g. `http://localhost:3000`).
