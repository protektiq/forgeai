# .NET API

The .NET API is a second, official API entry point. It validates an API key and proxies requests to Rails, forwarding correlation id and internal API key.

## Port

Default: **5001** (from `dotnet_api/Properties/launchSettings.json` `applicationUrl`).

## Authentication

- When `ApiKey` or `ASPNETCORE_API_KEY` is set (in config or env), all requests to `/api/*` must include header:
  - `X-Api-Key`: value matching the configured key
- Invalid or missing key: **401** with `{ "error": "Missing or invalid API key" }`.
- When no key is configured (e.g. development), all `/api` requests are allowed.

## Proxying to Rails

- The .NET API uses `Rails:BaseUrl` (default `http://localhost:3000`) and sends header `X-Internal-Api-Key` when `Rails:InternalApiKey` is set.
- Correlation id: `X-Correlation-Id` or `X-Request-Id` from the client request is forwarded to Rails; if absent, a new GUID is generated.
- Request/response bodies for generate and assets are passed through; status codes match Rails (or 502 on Rails connection/timeout errors).

## Endpoints

All are proxies to Rails; request and response JSON match the [Rails API](rails-api.md).

| Method | Path | Request | Response |
|--------|------|---------|----------|
| POST | /api/generate | JSON: `{ "prompt": "..." }` | Same as Rails POST /api/v1/generate: **201** `{ "job_id", "status": "queued" }` or **422** `{ "error" }`. On Rails unavailable/timeout: **502** `{ "error", "detail?" }`. |
| GET | /api/assets | Optional query: `?search=<query>` | Same as Rails GET /api/v1/assets: **200** array of asset objects. **502** if Rails unavailable. |
| GET | /api/assets/{id} | — | Same as Rails GET /api/v1/assets/:id: **200** asset object or **404**. **400** if id missing or invalid format. **502** if Rails unavailable. |

Note: Job status is not proxied at `/api/jobs/{id}`. Clients that need job polling can call Rails directly (with internal API key) at GET /api/v1/jobs/:id, or use another mechanism.

## Configuration / environment

| Source | Key | Purpose |
|--------|-----|---------|
| appsettings.json / appsettings.Development.json | `ApiKey` | API key for `X-Api-Key` validation. |
| Environment | `ASPNETCORE_API_KEY` | Overrides `ApiKey` when set. |
| appsettings*.json | `Rails:BaseUrl` | Rails base URL (e.g. `http://localhost:3000`). |
| appsettings*.json | `Rails:InternalApiKey` | Sent as `X-Internal-Api-Key` to Rails. |
| .env (root) | `Rails__BaseUrl`, `Rails__InternalApiKey`, `ApiKey` | Same when using .NET env/config binding. |
