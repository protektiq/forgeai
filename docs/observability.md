# Observability and diagnostics

This document describes the log shape and conventions used across the polyglot stack for debugging and operations.

## Correlation ID

- **Header:** All outbound HTTP requests from Rails to Python, C++, and Rust set the `X-Correlation-Id` header (see [generation_pipeline.rb](../rails_app/app/jobs/generation_pipeline.rb) and AssetsController for index `/ready` and `/search`).
- **Rails:** Set per request from `request.request_id` (or new UUID) in web and API controllers; set in background jobs from the job/run `correlation_id` and stored in `Thread.current[:correlation_id]` so the log formatter can include it.
- **Services:** Python, C++, Rust, and .NET read `X-Correlation-Id` (or `X-Request-Id`), log it, and return it in error response bodies (`error.correlation_id`).

## Structured logging

Each service emits machine-readable logs (JSON or key=value) with at least: **timestamp**, **service**, **level**, **correlation_id** (when available), **message**, and where applicable **error_code**.

### Rails (rails_app)

- **Format:** One JSON object per line to stdout/stderr (configurable via [config/initializers/structured_logging.rb](../rails_app/config/initializers/structured_logging.rb)).
- **Fields:** `timestamp` (ISO8601), `service` (`"rails_app"`), `level`, `message`, and when set `correlation_id` (from `Thread.current[:correlation_id]`).
- **Setting correlation_id:** Web/API requests set it in a before_action; jobs set it at the start of `perform` and clear in `ensure`.

### Python (python_gen)

- **Format:** One JSON object per line (see [main.py](../python_gen/main.py) `JsonLogFormatter`).
- **Fields:** `timestamp` (ISO8601), `service` (`"python_gen"`), `level`, `message`, and when present `correlation_id` (from request context). Optional `error_code` when logged with `extra={"error_code": "..."}`.

### C++ (cpp_media)

- **Format:** One JSON object per line to stderr (see [main.cpp](../cpp_media/main.cpp) `log_json`).
- **Fields:** `timestamp` (ISO8601), `service` (`"cpp_media"`), `level`, `correlation_id` (optional), `message`, and when applicable `error_code`.

### Rust (rust_index)

- **Format:** JSON lines from `tracing-subscriber` (see [main.rs](../rust_index/src/main.rs)).
- **Fields:** `timestamp`, `level`, `target` (crate/module, e.g. `rust_index`), `message`, and event fields such as `correlation_id`, `path`. Set `RUST_LOG=rust_index=info` to control level.

### .NET (dotnet_api)

- **Format:** One JSON object per line to console via `AddJsonConsole()` (see [Program.cs](../dotnet_api/Program.cs)).
- **Fields:** Standard Microsoft.Extensions.Logging JSON shape: timestamp, log level, category, message, and structured properties (e.g. `CorrelationId`, `Path` from the log call).

## Health endpoints

- **Python:** `GET /health` → `{"status":"ok","service":"python_gen"}`  
- **C++:** `GET /health` → `{"status":"ok","service":"cpp_media"}`  
- **Rust:** `GET /health` (200), `GET /ready` → `{"ready":true|false}`  
- **.NET:** `GET /health` → `{"status":"ok","service":"dotnet_api"}`  

Rails admin health dashboard probes these URLs and shows status and last-checked time.

## Workflow diagnostics

- **Workflow run detail:** `/workflow_runs/:id` shows step-by-step status, duration per step, output metadata, error messages, and correlation ID.
- **Recent failures:** `/admin/failures` lists recent failed workflow runs and failed generation jobs (legacy path) with correlation_id and links to run/job detail.
