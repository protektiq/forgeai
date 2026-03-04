# Python gen

FastAPI image generation service (Pillow placeholder MVP). Implements `POST /generate` and `GET /health`. By default returns raw PNG for Rails compatibility; use `Accept: application/json` to get JSON with `image_base64`, `seed`, and `model`.

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

## Endpoints

### GET /health

Health check for load balancers and runbooks.

```bash
curl http://localhost:5000/health
```

Response: `200` with JSON `{ "status": "ok", "service": "python_gen" }`.

### POST /generate

Generate an image for the given prompt.

- **Request:** JSON body `{ "prompt": "your text" }`. Prompt must be a non-empty string, max length 10,000 characters; control characters are rejected.
- **Default response (no `Accept: application/json`):** Raw PNG bytes with `Content-Type: image/png`. Use this for Rails and for saving to a file.
- **JSON response:** Send `Accept: application/json` to receive JSON `{ "image_base64": "<base64>", "seed": <number>, "model": "<string>" }`.

**Example: raw image (Rails / curl to file)**

```bash
curl -X POST -H "Content-Type: application/json" -d '{"prompt":"a cat"}' -o out.png http://localhost:5000/generate
```

**Example: JSON response**

```bash
curl -X POST -H "Content-Type: application/json" -H "Accept: application/json" -d '{"prompt":"a cat"}' http://localhost:5000/generate
```

## Port

Default port is 5000 (matches `GENERATOR_URL` used by the Rails app). To use another port:

```bash
uvicorn main:app --host 0.0.0.0 --port 5001
```

Then set `GENERATOR_URL` in the Rails app to `http://localhost:5001`.

## API docs

Interactive OpenAPI docs: **http://localhost:5000/docs**.
