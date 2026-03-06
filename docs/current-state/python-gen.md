# Python gen

Image generation service (FastAPI). Used by the Rails worker to produce images from a text prompt. Supports raw PNG or JSON response.

## Port

Default: **5000** (in code: `uvicorn.run(..., port=5000)`). Override via CLI: `uvicorn main:app --host 0.0.0.0 --port <port>`.

## Endpoints

### GET /health

Health check.

- **Response**: **200** `{ "status": "ok", "service": "python_gen" }`

### GET /

Root; describes available routes.

- **Response**: **200** `{ "service": "python_gen", "docs": "/docs", "health": "/health", "generate": "POST /generate" }`

### POST /generate

Generate an image for the given prompt.

**Request**

- **Content-Type**: `application/json`
- **Body**: `{ "prompt": "string" }`
  - `prompt`: Required, 1–10000 characters. Must not contain control characters (rejected with 422).

**Response (by Accept header)**

- **Accept: application/json** (or request includes `application/json` in Accept):
  - **200** `{ "image_base64": "<base64 PNG>", "seed": <int>, "model": "pillow-mvp" }`
  - Used by the Rails worker.
- **Other Accept** (default):
  - **200** Raw PNG body, `Content-Type: image/png`, `Content-Disposition: inline; filename="generated.png"`

**Errors**

- **422** — Validation error (e.g. prompt empty, too long, or contains control characters). Body: `{ "detail": "..." }` (FastAPI style).

## Optional headers

- **X-Correlation-Id** / **X-Request-Id**: Logged for request tracing; not required.

## Environment

- **PORT**: Optional; default 5000 is hardcoded when running via `python main.py` / uvicorn in code.
