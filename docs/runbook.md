# Runbook

How to build and run each service locally. For prerequisites and high-level "how to run everything," see the [top-level README](../README.md).

## Orchestration

Run each service in its own terminal from the corresponding folder. No startup order is required; services are independent. To run everything locally, open five terminals and run one service per terminal.

### First end-to-end win (Rails ↔ Python)

To verify prompt submission produces an image stored by Rails and visible in the asset library:

1. **Start the Python generator** (e.g. in `python_gen/`): `uvicorn main:app --host 0.0.0.0 --port 5000`. Leave it running.
2. **Set `GENERATOR_URL`** (optional): Default is `http://localhost:5000`. If python_gen runs on another host/port, set `GENERATOR_URL` in the environment before starting Rails/Sidekiq (e.g. `export GENERATOR_URL=http://localhost:5001`).
3. **Start Rails** and **Sidekiq** (Redis must be running): In `rails_app/`, run `bundle exec rails s` in one terminal and `bundle exec sidekiq` in another.
4. In the browser: sign in, open the dashboard, submit a prompt, click Generate. Refresh until the job status is completed, then open "View asset" or the Asset library; the new asset should appear with file and generator metadata (seed, model).

## 10-prompt batch (exit criteria)

To verify the demo runs a small batch without silent failures:

1. **Start all services** (Rails, Sidekiq, Python gen; optionally C++ media, Rust index, dotnet_api).
2. **Rate limit:** Prompt creation (POST `/api/v1/generate` and POST `/dashboard`) is limited to **30 requests per minute per IP** by default. For a 10-prompt batch, stay under that limit or set `RACK_ATTACK_THROTTLE_LIMIT=40` (or higher) in the Rails env before starting.
3. **Run 10 prompts** either:
   - From the dashboard: submit 10 different prompts (one at a time or in quick succession), then refresh; or
   - Via API: `for i in 1 2 3 4 5 6 7 8 9 10; do curl -s -X POST http://localhost:3000/api/v1/generate -H "Content-Type: application/json" -H "X-Internal-Api-Key: YOUR_KEY" -d "{\"prompt\":\"test prompt $i\"}"; done` (omit the header if `RAILS_INTERNAL_API_KEY` is not set).
4. **Check results:** Use the dashboard "Recent jobs" and open **View job** on any job to see full status and error message. Failed jobs show the full error on the Job details page (`/jobs/:id`). API clients can poll `GET /api/v1/jobs/:id` for status and `error_message`.
5. **Correlation in logs:** Each job has a `correlation_id` (from the request that created it). Rails logs it at job start; outbound calls to Python, C++, and Rust send `X-Correlation-Id`. Grep logs by that id to trace a single job across services.

### Rails app (`rails_app/`)

```bash
cd rails_app
bundle install
bundle exec rails s
```

- **Port:** 3000  
- **Logs:** stdout; also `rails_app/log/development.log` if present  
- **Common issues:** Port 3000 in use → change with `-p 3001` or stop the other process.
- **Rate limiting:** Prompt creation (dashboard and API) is throttled per IP (default 30/min). Set `RACK_ATTACK_THROTTLE_LIMIT` to adjust. See [.env.example](../.env.example) for timeout/retry and rate-limit env vars. (`python_gen/`)

```bash
cd python_gen
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 5000
```

- **Port:** 5000  
- **Logs:** stdout  
- **Common issues:** Port 5000 in use → use `--port 5001` and set Rails `GENERATOR_URL` accordingly; missing venv → ensure you activate before `pip install`.

### C++ media (`cpp_media/`)

```bash
cd cpp_media
make
./hello
```

- **Logs:** stdout (no server; one-shot binary)  
- **Common issues:** No `make` → use `g++ -o hello main.cpp` then `./hello`; see `cpp_media/README.md`.

### Rust index (`rust_index/`)

```bash
cd rust_index
cargo build
cargo run
```

- **Logs:** stdout (one-shot binary)  
- **Common issues:** First run may download toolchain; see `rust_index/README.md`.

### .NET API (`dotnet_api/`)

```bash
cd dotnet_api
dotnet restore
dotnet build
dotnet run
```

- **Port:** 5000 (HTTP), 5001 (HTTPS) — check app output  
- **Logs:** stdout  
- **Common issues:** Port in use → configure in `Properties/launchSettings.json` or app configuration; see `dotnet_api/README.md`.

## Troubleshooting

- **Port already in use:** Change the port in the app config or stop the process using the port (`lsof -i :PORT` on Unix).
- **Build failures:** Ensure prerequisites are installed (Ruby, Python, g++, Rust, .NET SDK) and you are in the correct folder; see each project's README.

For architecture overview and data flow, see [architecture.md](architecture.md) and [data-flow.md](data-flow.md).
