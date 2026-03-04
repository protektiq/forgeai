# Rails app

Rails is the system of record and user-facing product. Users sign in with Devise, submit prompts on the dashboard (creating `GenerationJob` records with status `queued`), and a background job runs the generation pipeline. Users can browse the asset library and asset detail pages.

## Prerequisites

- **Ruby** 3.x
- **Bundler** (`gem install bundler`)
- **Redis** (for Sidekiq; optional: use `config.active_job.queue_adapter = :async` in development for minimal setup without Redis)

## Setup

```bash
bundle install
bundle exec rails db:migrate
```

Ensure Redis is running (e.g. `redis-server`) if you use Sidekiq. Default Redis URL: `redis://localhost:6379/0`. Override with `REDIS_URL` if needed.

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

## Pipeline (generation job)

Clicking **Generate** on the dashboard creates a `GenerationJob` with status `queued` and enqueues `GenerateAssetJob`. The worker:

1. Marks the job `running`
2. Calls the **Python generator** (HTTP POST to `GENERATOR_URL/generate` with `{ "prompt": "..." }`; expects image bytes in the response)
3. Stores the image in Active Storage and creates an `Asset` linked to the job
4. Optionally runs the **C++ media** command (env: `INPUT_PATH`, `ASSET_ID`, `PROMPT`)
5. Optionally runs the **Rust index** command (env: `ASSET_ID`, `PROMPT`)
6. Marks the job `completed` or `failed` (with `error_message`)

**Environment variables (optional):**

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection for Sidekiq |
| `GENERATOR_URL` | `http://localhost:5000` | Base URL of the Python generator service (e.g. Flask on port 5000) |
| `MEDIA_SERVICE_COMMAND` | (blank) | Command to run for C++ post-processing; skipped if blank |
| `INDEX_SERVICE_COMMAND` | (blank) | Command to run for Rust indexing; skipped if blank |

The Python service must implement `POST /generate` returning image bytes (e.g. `Content-Type: image/png`). If the generator is not running or returns an error, the job is marked `failed` with an error message. C++ and Rust steps are skipped when their commands are not set.

## Usage

- **Root (/)** — Redirects to dashboard when signed in, or to sign-in when not.
- **Sign up / Sign in** — Devise routes (e.g. `/users/sign_up`, `/users/sign_in`). After sign-in you are redirected to the dashboard.
- **Dashboard** — Submit a prompt and click **Generate** to create a queued job and start the background pipeline. Recent jobs show status: queued, running, completed, or failed (with error message). Refresh the page to see updates.
- **Asset library** — List of your assets (after completed generations).
- **Asset detail** — View metadata, linked job prompt/status, and download the stored file.

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
