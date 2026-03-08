# Python gen

FastAPI image generation service with **pluggable backends** (default: Pillow placeholder MVP). Implements `POST /generate` and `GET /health`. By default returns raw PNG for Rails compatibility; use `Accept: application/json` to get JSON with `image_base64`, `seed`, `model`, `backend`, and `duration_ms`.

## Prerequisites

- **Python** 3.x
- Recommended: create a virtual environment before installing dependencies

## Build

```bash
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## Run

```bash
uvicorn main:app --host 0.0.0.0 --port 5000
```

Or run the module directly (after activating venv):

```bash
python main.py
```

Server listens on **http://localhost:5000**.

## Backend selection

Generation is handled by a **backend** (e.g. Pillow placeholder, future local model). Backend can be chosen by:

1. **Request body:** Optional `backend` in POST /generate (e.g. `{ "prompt": "a cat", "backend": "pillow_mock" }`).
2. **Environment:** `GENERATOR_BACKEND` (default `pillow_mock`).

Resolution order: request body `backend` (if present) → `GENERATOR_BACKEND` env → `pillow_mock`.

Available backends:

- **pillow_mock** (default) — Pillow placeholder: draws prompt text on a solid image. Model id: `pillow-mvp`.
- **local_model** — Stub only; returns 501 until a real implementation is wired.
- **test_stub** — Test-only: deterministic output for tests.

Rails can pass `backend` in the request body when calling the generator (e.g. from workflow step config).

## Endpoints

### GET /health

Health check for load balancers and runbooks.

```bash
curl http://localhost:5000/health
```

Response: `200` with JSON `{ "status": "ok", "service": "python_gen" }`.

### POST /generate

Generate an image for the given prompt.

- **Request:** JSON body `{ "prompt": "your text" }`. Optional: `"backend": "pillow_mock"` to override backend for this request. Prompt must be a non-empty string, max length 10,000 characters; control characters are rejected.
- **Default response (no `Accept: application/json`):** Raw PNG bytes with `Content-Type: image/png`. Use this for Rails and for saving to a file.
- **JSON response:** Send `Accept: application/json` to receive JSON:
  - `image_base64` — PNG image as base64
  - `seed` — seed used for generation
  - `model` — model name (e.g. `pillow-mvp`)
  - `backend` — backend id that produced the image (e.g. `pillow_mock`)
  - `duration_ms` — generation time in milliseconds

**Example: raw image (Rails / curl to file)**

```bash
curl -X POST -H "Content-Type: application/json" -d '{"prompt":"a cat"}' -o out.png http://localhost:5000/generate
```

**Example: JSON response**

```bash
curl -X POST -H "Content-Type: application/json" -H "Accept: application/json" -d '{"prompt":"a cat"}' http://localhost:5000/generate
```

**Example: override backend for this request**

```bash
curl -X POST -H "Content-Type: application/json" -H "Accept: application/json" -d '{"prompt":"a cat","backend":"pillow_mock"}' http://localhost:5000/generate
```

## Port

Default port is 5000 (matches `GENERATOR_URL` used by the Rails app). To use another port:

```bash
uvicorn main:app --host 0.0.0.0 --port 5001
```

Then set `GENERATOR_URL` in the Rails app to `http://localhost:5001`.

## API docs

Interactive OpenAPI docs: **http://localhost:5000/docs**.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GENERATOR_BACKEND` | `pillow_mock` | Default backend id when request does not specify `backend`. Options: `pillow_mock`, `local_model`, `test_stub`. |

## Test instructions

From `python_gen/` (with venv activated, or use `python_gen/.venv/bin/pytest`):

```bash
pytest tests -v
```

See [docs/testing.md](../docs/testing.md) for contract and malformed input tests.
