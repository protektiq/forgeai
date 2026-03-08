# forgeai

Multi-language repo: each service is built and run independently. This document gives prerequisites, repository layout, **first-time setup**, startup order, required env vars, health endpoints, and how to run everything locally. For architecture and operations, see [docs/architecture.md](docs/architecture.md) and [docs/runbook.md](docs/runbook.md). API error responses follow a [standard shape](docs/contracts/error-response.md) (`error.code`, `error.message`, `error.correlation_id`) across all services.

## First-time setup

To get the whole platform running without hunting through each service's README:

1. **Bootstrap** (install deps, create DB, copy `.env` if missing):
   ```bash
   ./scripts/bootstrap.sh
   ```
2. **Start Redis** if you use Sidekiq: `redis-server` (or skip and use Rails async job adapter in development).
3. **Run the stack** (all services in the background, logs under `logs/`):
   ```bash
   ./scripts/run_all.sh
   ```
   To stop: `./scripts/run_all.sh stop`. For debugging, run each service in a separate terminal (see [Startup order](#startup-order) and [docs/runbook.md](docs/runbook.md)).
4. **Health-only smoke check** (quick “are services up?”):
   ```bash
   ./scripts/smoke_test.sh
   ```
   For a **full E2E** test (create job → generate → process → index → verify asset and search), use: `E2E=1 ./scripts/e2e_smoke.sh`. See [docs/testing.md](docs/testing.md).

## Repository layout

| Folder | Description |
|--------|-------------|
| `rails_app/` | Rails web app and API (system of record) |
| `python_gen/` | FastAPI image generation service |
| `cpp_media/` | C++ HTTP service (thumbnails/processing) |
| `rust_index/` | Rust HTTP service (index/search) |
| `dotnet_api/` | .NET API (proxy + API key auth) |
| `docs/` | Architecture, runbook, data-flow, [current-state](docs/current-state/) contracts |

## Prerequisites

Install the following per service you want to run:

| Service       | Prerequisites                          | Notes                    |
|---------------|----------------------------------------|--------------------------|
| Rails app     | Ruby 3.x, Bundler                      | `gem install bundler`    |
| Python gen    | Python 3.x                             | Use a venv recommended   |
| C++ media     | g++ (C++17), make, libvips             | See [cpp_media/README.md](cpp_media/README.md) |
| Rust index    | Rust (rustc, cargo)                   | Install via [rustup](https://rustup.rs/) |
| .NET API      | .NET SDK 8.0                           | [Download](https://dotnet.microsoft.com/download) |

You do not need all of them to run a single service; install only what you need for the folders you use.

## Startup order

When running the full stack locally, use this order:

1. **Redis** — Required for Sidekiq. Start first (e.g. `redis-server`).
2. **Python gen** — Rails worker calls `GENERATOR_URL` (default `http://localhost:5000`). Start before or with Rails.
3. **Optional HTTP services** — C++ media (`./cpp_media`), Rust index (`cargo run`) if you use `CPP_MEDIA_URL` / `INDEX_SERVICE_URL`.
4. **Rails** — `bundle exec rails s`. Depends on Redis if using Sidekiq.
5. **Sidekiq** — `bundle exec sidekiq` (in another terminal). Consumes jobs that call Python/C++/Rust.
6. **.NET API** (optional) — `dotnet run`. Proxies to Rails; start after Rails if using it.

## How to run everything locally

Run each service in its own terminal from the corresponding folder. See [Startup order](#startup-order) above for the recommended sequence.

### Rails app (`rails_app/`)

```bash
cd rails_app
bundle install
bundle exec rails s
```

- **URL:** http://localhost:3000  
- **Details:** [rails_app/README.md](rails_app/README.md)

### Python gen (`python_gen/`)

```bash
cd python_gen
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

Or equivalently: `uvicorn main:app --host 0.0.0.0 --port 5000`

- **URL:** http://localhost:5000  
- **Details:** [python_gen/README.md](python_gen/README.md)

### C++ media (`cpp_media/`)

```bash
cd cpp_media
make
./cpp_media [port]
```

Default port is **8080** (omit `[port]` or pass e.g. `./cpp_media 8080`). HTTP server with GET /health, POST /process.

- **URL:** http://localhost:8080  
- **Details:** [cpp_media/README.md](cpp_media/README.md)

### Rust index (`rust_index/`)

```bash
cd rust_index
cargo build
cargo run
```

HTTP server on port **3132** (override with env `PORT`). GET /health, POST /index, GET /search.

- **URL:** http://localhost:3132  
- **Details:** [rust_index/README.md](rust_index/README.md)

### .NET API (`dotnet_api/`)

```bash
cd dotnet_api
dotnet restore
dotnet build
dotnet run
```

- **URL:** http://localhost:5001  
- **Details:** [dotnet_api/README.md](dotnet_api/README.md)

## Required environment variables

For **minimal local run**, no env vars are required; Rails defaults `GENERATOR_URL=http://localhost:5000` and `REDIS_URL=redis://localhost:6379/0`. For **E2E with Sidekiq**, ensure Redis is running or set `REDIS_URL`. For **production-like** setups, set secrets and Redis explicitly.

| Variable | Service | Required? | Default / notes |
|----------|---------|-----------|-----------------|
| `REDIS_URL` | Rails | For Sidekiq | `redis://localhost:6379/0` |
| `GENERATOR_URL` | Rails | No | `http://localhost:5000` |
| `CPP_MEDIA_URL` | Rails | No | Blank; set to use C++ media (e.g. `http://localhost:8080`) |
| `INDEX_SERVICE_URL` | Rails | No | Blank; set to use Rust index (e.g. `http://localhost:3132`) |
| `RAILS_INTERNAL_API_KEY` | Rails | Production | When set, internal API requires `X-Internal-Api-Key` |
| `Rails__BaseUrl` | .NET API | No | `http://localhost:3000` |
| `Rails__InternalApiKey` | .NET API | When Rails uses key | Sent as `X-Internal-Api-Key` to Rails |
| `ApiKey` / `ASPNETCORE_API_KEY` | .NET API | No | When set, requests need `X-Api-Key` |
| `PORT` | Rust index | No | 3132 |
| `PORT` | Python gen | No | 5000 in code; use uvicorn `--port` to override |

Full list: [.env.example](.env.example) and [docs/current-state/](docs/current-state/) (ports, env vars, API contracts).

## Health endpoints

| Service     | Health endpoint | Example (default port) |
|-------------|-----------------|------------------------|
| Rails       | —               | (none; no health route) |
| Python gen  | GET /health     | http://localhost:5000/health |
| C++ media   | GET /health     | http://localhost:8080/health |
| Rust index  | GET /health     | http://localhost:3132/health |
| .NET API    | GET /health     | http://localhost:5001/health |

Rails does not expose a health endpoint today.

## Common troubleshooting

- **Port already in use** — Change the port in the app config or stop the process (`lsof -i :PORT` on Unix). See [docs/runbook.md](docs/runbook.md).
- **Redis not running** — Sidekiq will fail. Start Redis (e.g. `redis-server`) or set `REDIS_URL` to your instance.
- **Rate limiting (429)** — Prompt creation is throttled per IP (default 30/min). Set `RACK_ATTACK_THROTTLE_LIMIT` in Rails env; see [.env.example](.env.example).
- **Generator / media / index not reached** — Ensure URLs match where services run: `GENERATOR_URL`, `CPP_MEDIA_URL`, `INDEX_SERVICE_URL`. Use `correlation_id` in logs and [docs/runbook.md](docs/runbook.md) to trace requests across services.
- **Build failures** — Check prerequisites (Ruby, Python, g++, Rust, .NET SDK) and each service’s README in its folder.

For full runbook and E2E verification steps, see [docs/runbook.md](docs/runbook.md).

**Optional — Docker:** After the non-container flow is stable, you can run the stack with Docker Compose: `docker compose -f docker-compose.dev.yml up --build`. This requires a Dockerfile in each service directory (see [docker-compose.dev.yml](docker-compose.dev.yml)); prefer the scripts above if you are still changing the local setup.

## Docs

- **[docs/architecture.md](docs/architecture.md)** — Service overview and local orchestration.
- **[docs/runbook.md](docs/runbook.md)** — Build/run commands and troubleshooting.
- **[docs/data-flow.md](docs/data-flow.md)** — Data flow diagram (updated as the system evolves).
- **[docs/current-state/](docs/current-state/)** — Single reference for API contracts, ports, and env vars.
