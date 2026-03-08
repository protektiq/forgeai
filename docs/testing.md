# Testing

This document describes how to run contract tests, malformed-input tests, **health-only smoke**, and the **end-to-end smoke** test.

## Health-only smoke test

Quick check that all services are reachable (no generation or jobs).

- **Script:** `scripts/smoke_test.sh`
- **Run:** `./scripts/smoke_test.sh`
- **Checks:** GET /health on Python gen, cpp_media, rust_index, dotnet_api; GET / on Rails (expect 200 or 302).
- **Override URLs:** Set `GENERATOR_URL`, `CPP_MEDIA_URL`, `INDEX_SERVICE_URL`, `RAILS_URL`, `DOTNET_API_URL` if services run elsewhere.

## End-to-end smoke test

A single automated flow: create workflow run → generate → process → index → verify asset exists → verify search finds it.

- **Script:** `scripts/e2e_smoke.sh`
- **Requires:** All services running (Rails, Sidekiq, Python gen, C++ media, Rust index). Optional: Rails internal API key if configured.
- **Run:** `E2E=1 ./scripts/e2e_smoke.sh`
- **Env:** `RAILS_URL` (default `http://localhost:3000`), `RAILS_INTERNAL_API_KEY` (if Rails requires it)

The script creates a generation with a unique prompt, polls the job until completed, then checks that the asset is returned by GET /api/v1/assets?search=...

## Service-level contract tests

Each service has contract tests that assert its HTTP API matches the contracts in `docs/contracts/`.

### Python gen (`python_gen`)

- **Location:** `python_gen/tests/`
- **Run:** From `python_gen/`: `pytest tests -v` (or use the project venv: `python_gen/.venv/bin/pytest tests -v`)
- **Contract:** `docs/contracts/python_gen.yaml`
- **Tests:** `test_contract.py` (GET /health, POST /generate), `test_malformed.py` (invalid prompt cases)

### C++ media (`cpp_media`)

- **Location:** `contract_tests/` at repo root
- **Run:** From repo root, with **cpp_media binary running** on port 8080 (or set `CPP_MEDIA_URL`):
  ```bash
  CPP_MEDIA_URL=http://localhost:8080 python_gen/.venv/bin/pytest contract_tests -v
  ```
- **Contract:** `docs/contracts/cpp_media.yaml`
- **Tests:** `test_cpp_media_contract.py` (GET /health, POST /process), `test_cpp_media_malformed.py` (invalid bodies)

### Rust index (`rust_index`)

- **Location:** `rust_index/tests/`
- **Run:** From `rust_index/`: `cargo test`
- **Contract:** `docs/contracts/rust_index.yaml`
- **Tests:** `api_contract.rs` (GET /health, POST /index, GET /search), `persistence.rs` (restart persistence)

### .NET API (`dotnet_api`)

- **Location:** `dotnet_api.Tests/`
- **Run:** From repo root: `dotnet test dotnet_api.Tests/dotnet_api.Tests.csproj`
- **Contract:** `docs/contracts/public-api-v1.yaml`
- **Tests:** Contract (health, API shape), API key validation and malformed generate input

### Rails (`rails_app`)

- **Location:** `rails_app/spec/requests/api/v1/`
- **Run:** From `rails_app/`: `bundle exec rspec spec/requests/api/v1/generate_controller_spec.rb`
- **Contract:** Workflow creation endpoints (POST /api/v1/generate with/without workflow_slug)
- **Tests:** Contract (201 + job_id or workflow_run_id), malformed (missing/long prompt, invalid workflow_id/slug)

## End-to-end smoke test

A single automated flow: create workflow run → generate → process → index → verify asset exists → verify search finds it.

- **Script:** `scripts/e2e_smoke.sh`
- **Requires:** All services running (Rails, Sidekiq, Python gen, C++ media, Rust index). Optional: Rails internal API key if configured.
- **Run:** `E2E=1 ./scripts/e2e_smoke.sh`
- **Env:** `RAILS_URL` (default `http://localhost:3000`), `RAILS_INTERNAL_API_KEY` (if Rails requires it)

The script creates a generation with a unique prompt, polls the job until completed, then checks that the asset is returned by GET /api/v1/assets?search=...

(For a quick health-only check, use `./scripts/smoke_test.sh` instead.)

## Malformed input tests

Covered by the same suites above:

- **C++:** `contract_tests/test_cpp_media_malformed.py` (empty body, missing/empty/invalid image_base64, wrong content-type)
- **Python:** `python_gen/tests/test_malformed.py` (missing/empty/too-long/control-char/non-string prompt)
- **Rails:** `rails_app/spec/requests/api/v1/generate_controller_spec.rb` (missing/blank/too-long prompt, invalid workflow_id/slug)
- **.NET:** `dotnet_api.Tests/ApiKeyValidationTests.cs` (API key required/wrong/valid, empty/missing prompt)

## Restart persistence test (Rust)

Verifies that after indexing an asset and “restarting” the Rust service (new process loading from the same SQLite path), search still returns the asset.

- **Run:** `cargo test` in `rust_index/` (includes `tests/persistence.rs`)

## CI

- **Unit/contract/malformed:** Run per service (pytest, cargo test, dotnet test, rspec) in parallel.
- **E2E smoke:** Run only when E2E is enabled (e.g. `E2E=1 ./scripts/e2e_smoke.sh`), typically after bringing the full stack up (e.g. docker-compose or a dedicated E2E job).
