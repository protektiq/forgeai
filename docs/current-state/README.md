# Current state: contracts and configuration

Current API contracts, ports, and environment variables as of documentation. Use this folder as the single reference for what each service exposes and how they connect.

## Ports

| Service     | Default port | Override |
|------------|--------------|----------|
| Rails      | 3000         | `rails s -p <port>` |
| .NET API   | 5001         | `applicationUrl` in `dotnet_api/Properties/launchSettings.json` |
| Python gen | 5000         | `uvicorn ... --port <port>` or `PORT` (if supported by run script) |
| Rust index | 3132         | Env `PORT` |
| C++ media  | 8080         | First command-line argument `argv[1]` |

## Environment variables

| Variable | Service | Purpose |
|----------|---------|---------|
| `GENERATOR_URL` | Rails | Base URL of Python generator (e.g. `http://localhost:5000`) |
| `CPP_MEDIA_URL` | Rails | Base URL of C++ media HTTP service (e.g. `http://localhost:8080`). When set, worker POSTs image to `/process` and attaches thumbnail. |
| `INDEX_SERVICE_URL` | Rails | Base URL of Rust index (e.g. `http://localhost:3132`). When set, worker POSTs to `/index` and asset list search uses GET `/search?q=...`. |
| `MEDIA_SERVICE_COMMAND` | Rails | Optional CLI command for C++ media when `CPP_MEDIA_URL` is not set (env: `INPUT_PATH`, `ASSET_ID`, `PROMPT`). |
| `INDEX_SERVICE_COMMAND` | Rails | Optional CLI command for indexing when `INDEX_SERVICE_URL` is not set (env: `ASSET_ID`, `PROMPT`). |
| `GENERATOR_OPEN_TIMEOUT` | Rails | Seconds for generator connection (default 10). |
| `GENERATOR_READ_TIMEOUT` | Rails | Seconds for generator response (default 60). |
| `GENERATOR_RETRIES` | Rails | Retry count for generator HTTP (default 2). |
| `MEDIA_OPEN_TIMEOUT` | Rails | Seconds for media service connection (default 10). |
| `MEDIA_READ_TIMEOUT` | Rails | Seconds for media service response (default 60). |
| `MEDIA_RETRIES` | Rails | Retry count for media HTTP (default 2). |
| `INDEX_OPEN_TIMEOUT` | Rails | Seconds for index service connection (default 10). |
| `INDEX_READ_TIMEOUT` | Rails | Seconds for index service response (default 10). |
| `INDEX_RETRIES` | Rails | Retry count for index HTTP (default 2). |
| `API_USER_ID` | Rails | User ID for internal API scope (optional; dev fallback: first user). |
| `RAILS_INTERNAL_API_KEY` | Rails | When set, internal API requires header `X-Internal-Api-Key`. |
| `HOST_FOR_BLOB_URLS` | Rails | Base host for asset `download_url` in API (e.g. `https://app.example.com`). |
| `REDIS_URL` | Rails | Redis URL for Sidekiq (e.g. `redis://localhost:6379/0`). |
| `RACK_ATTACK_THROTTLE_LIMIT` | Rails | Max prompt-create requests per IP per minute (default 30). |
| `Rails__BaseUrl` | .NET API | Rails base URL for proxy (e.g. `http://localhost:3000`). |
| `Rails__InternalApiKey` | .NET API | Sent as `X-Internal-Api-Key` when calling Rails. |
| `ApiKey` | .NET API | API key validated via `X-Api-Key`; when set, requests without valid key get 401. |
| `ASPNETCORE_API_KEY` | .NET API | Alternative to `ApiKey` in config. |
| `PORT` | Rust index | HTTP port (default 3132). |
| `PORT` | Python gen | Optional; default 5000 in code. |
| (argv[1]) | C++ media | Optional port; default 8080. |

## Service index

- [Rails API (v1)](rails-api.md) — Internal API: generate, jobs, assets. Auth: `X-Internal-Api-Key`; scoped to API user.
- [.NET API](dotnet-api.md) — Proxy + API key auth; forwards to Rails.
- [Python gen](python-gen.md) — POST /generate (image generation).
- [Rust index](rust-index.md) — POST /index, GET /search.
- [C++ media](cpp-media.md) — POST /process (thumbnail/resize).
- [Data flow](data-flow.md) — Who calls whom and which contracts are used.

For the full system diagram and runbook, see [../data-flow.md](../data-flow.md) and [../runbook.md](../runbook.md).
