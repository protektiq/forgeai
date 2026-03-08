# Rails app

Rails is the system of record and user-facing product. Orchestration is **workflow-centric**: every run is a **WorkflowRun** with **WorkflowRunSteps**. Users sign in with Devise, submit prompts on the dashboard (creating a default WorkflowRun + steps + **GenerationJob** with status `queued`), and a background job runs the generation pipeline. Alternatively, the API can accept a **workflow_id** or **workflow_slug** to run a preset workflow via **OrchestrateWorkflowJob**. Users can browse the asset library and asset detail pages.

## Prerequisites

- **Ruby** 3.x
- **Bundler** (`gem install bundler`)
- **Redis** (for Sidekiq; optional: use `config.active_job.queue_adapter = :async` in development for minimal setup without Redis)

## Setup

```bash
bundle install
bundle exec rails db:migrate
bundle exec rails db:seed
```

Ensure Redis is running (e.g. `redis-server`) if you use Sidekiq. Default Redis URL: `redis://localhost:6379/0`. Override with `REDIS_URL` if needed. **Seeds** create three workflow presets: `generate_only`, `generate_thumbnail`, `generate_process_index` (default for dashboard/API when no workflow is specified). Seeds also create **demo users** (`demo@example.com` / `api@example.com`) and sample workflow runs and assets. To use the .NET gateway with the API user, set `API_USER_ID` to the id of `api@example.com` (printed in seed output).

## Run

Run both the web server and the job worker:

```bash
# Terminal 1: Rails
bundle exec rails s

# Terminal 2: Sidekiq (processes background jobs)
bundle exec sidekiq
```

Server listens on **http://localhost:3000**.

**Minimal setup (no Redis):** In `config/environments/development.rb` set `config.active_job.queue_adapter = :async` so jobs run in-process. No Sidekiq or Redis required; jobs are not persisted across restarts. For production, use Sidekiq + Redis.

## Pipeline (generation and workflows)

**Dashboard / API without workflow (wrapped path):** Clicking **Generate** on the dashboard (or `POST /api/v1/generate` with only `prompt`) creates a **WorkflowRun** (default preset `generate_process_index`) and **WorkflowRunSteps**, then a **GenerationJob** linked to the run with status `queued`, and enqueues **GenerateAssetJob**. The worker runs the full pipeline and updates the WorkflowRun and steps on completion or failure.

**API with workflow:** `POST /api/v1/generate` with `workflow_id` or `workflow_slug` creates a **WorkflowRun** and **WorkflowRunSteps** from that preset and enqueues **OrchestrateWorkflowJob**, which executes each step in order (generate → store → thumbnail → index, depending on the preset). Response: `{ workflow_run_id, status: "queued" }`.

The worker (GenerateAssetJob or OrchestrateWorkflowJob):

1. Marks the job `running`
2. Calls the **Python generator** (HTTP POST to `GENERATOR_URL/generate` with `{ "prompt": "..." }` and optional `"backend"`; expects JSON with `image_base64`, `seed`, `model`, `backend`, `duration_ms` when using `Accept: application/json`)
3. Stores the image in Active Storage and creates an `Asset` linked to the job (with generator metadata: seed, model, backend, duration_ms). Workflow generate steps can pass a step `config["backend"]` to override the default backend for that run.
4. Optionally calls the **C++ media** service:
   - **HTTP** (when `CPP_MEDIA_URL` is set): POSTs the image to `CPP_MEDIA_URL/process`, receives thumbnail (and optionally processed) in JSON, and attaches the thumbnail to the Asset. The asset library and asset detail pages then show thumbnails when present.
   - **CLI** (when `MEDIA_SERVICE_COMMAND` is set and `CPP_MEDIA_URL` is blank): runs the command with env `INPUT_PATH`, `ASSET_ID`, `PROMPT` (no thumbnail attachment)
5. Optionally calls the **Rust index** service:
   - **HTTP** (when `INDEX_SERVICE_URL` is set): POSTs to `INDEX_SERVICE_URL/index` with JSON `{ asset_id, prompt, metadata, tags }` so assets can be searched later. The asset library search box uses GET `INDEX_SERVICE_URL/search?q=...` to find matching asset IDs and filters the list accordingly.
   - **CLI** (when `INDEX_SERVICE_COMMAND` is set and `INDEX_SERVICE_URL` is blank): runs the command with env `ASSET_ID`, `PROMPT` (no HTTP indexing)
6. Marks the job `completed` or `failed` (with `error_message`). When the run was created via the wrapped path, the worker also updates the **WorkflowRun** and **WorkflowRunSteps** status.

**Environment variables (optional):** See the repo root [.env.example](../../.env.example) for a single reference of all env vars (Rails, dotnet_api, timeouts, retries, rate limit).

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection for Sidekiq |
| `GENERATOR_URL` | `http://localhost:5000` | Base URL of the Python generator service (e.g. Flask on port 5000) |
| `GENERATOR_BACKEND` | `pillow_mock` | Generator backend id used when the request does not override it (e.g. from workflow step config). Options: `pillow_mock` (default), `local_model` (stub), `test_stub` (tests). |
| `CPP_MEDIA_URL` | (blank) | Base URL of the C++ media HTTP service (e.g. `http://localhost:8080`). When set, the job POSTs the image to `/process` and attaches the returned thumbnail to the Asset; thumbnails are shown in the asset library and asset detail. |
| `MEDIA_SERVICE_COMMAND` | (blank) | Fallback: command to run for C++ post-processing when `CPP_MEDIA_URL` is not set; skipped if blank |
| `INDEX_SERVICE_URL` | (blank) | Base URL of the Rust index HTTP service (e.g. `http://localhost:3132`). When set, the job POSTs to `/index` after each asset creation and the asset library search box uses GET `/search?q=...` to filter assets by prompt/metadata. |
| `INDEX_SERVICE_COMMAND` | (blank) | Fallback: command to run for Rust indexing when `INDEX_SERVICE_URL` is not set; skipped if blank |
| `GENERATOR_OPEN_TIMEOUT`, `GENERATOR_READ_TIMEOUT`, `GENERATOR_RETRIES` | 10, 60, 2 | Timeouts (seconds) and retry count for generator HTTP calls. |
| `MEDIA_OPEN_TIMEOUT`, `MEDIA_READ_TIMEOUT`, `MEDIA_RETRIES` | 10, 60, 2 | Timeouts and retries for C++ media HTTP. |
| `INDEX_OPEN_TIMEOUT`, `INDEX_READ_TIMEOUT`, `INDEX_RETRIES` | 10, 10, 2 | Timeouts and retries for Rust index HTTP. |
| `RACK_ATTACK_THROTTLE_LIMIT` | 30 | Max prompt-create requests per IP per minute (dashboard and API). |

The Python service must implement `POST /generate` and return JSON (when requested with `Accept: application/json`) containing `image_base64`, `seed`, `model`, `backend`, and `duration_ms`. If the generator is not running or returns an error, the job is marked `failed` with an error message. When `CPP_MEDIA_URL` is set, start the cpp_media service (see `cpp_media/README.md`); the job will send the generated image there and attach the returned thumbnail to the Asset. The asset library displays thumbnails when attached; the asset detail page shows both the original image and the thumbnail. When `INDEX_SERVICE_URL` is set, start the Rust index service (see `rust_index/README.md`); the job will POST each new asset to `/index`, and the asset library search box will call GET `/search?q=...` to show matching assets. C++ CLI and Rust CLI steps are used only when their URL is not set but their command is set.

## Usage

- **Root (/)** — Redirects to dashboard when signed in, or to sign-in when not.
- **Sign up / Sign in** — Devise routes (e.g. `/users/sign_up`, `/users/sign_in`). After sign-in you are redirected to the dashboard.
- **Dashboard** — Submit a prompt and click **Generate** to create a queued job and start the background pipeline. Recent jobs show status: queued, running, completed, or failed (with error message). Click **View job** to open the Job details page (full error when failed). Refresh the page to see updates.
- **Job details** (`/jobs/:id`) — Full job status, prompt, timestamps, and full error message when failed; link to asset when completed.
- **Asset library** — List of your assets (after completed generations). Use the search box to filter by prompt or metadata when the Rust index service is configured (`INDEX_SERVICE_URL`). When the C++ media service is used, thumbnails are shown for each asset when available; otherwise a "No preview" placeholder is shown.
- **Asset detail** — View metadata, linked job prompt/status, the main image and thumbnail (when attached), and download the stored file.

## Database

- **Default:** SQLite (`db/development.sqlite3`). No extra setup.
- **Postgres:** Replace `sqlite3` with `pg` in the Gemfile, update `config/database.yml`, then `rails db:create db:migrate`.

## Customize Devise views

To edit sign-in/sign-up forms and emails:

```bash
bundle exec rails generate devise:views
```

Then edit the generated templates under `app/views/devise/`.

## Port

Default port is 3000. To use another port:

```bash
bundle exec rails s -p 3001
```

## Test instructions

From `rails_app/`:

```bash
bundle exec rspec spec/requests/api/v1/generate_controller_spec.rb
```

For contract/malformed and full test layout, see [docs/testing.md](../docs/testing.md).
