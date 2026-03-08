# cpp_media

HTTP service for image processing: resize, format conversion (e.g. PNG → JPG), and thumbnail generation. Used by the Rails app to produce thumbnails and optionally resized images for the asset library.

## Prerequisites

- **C++17 compiler** (e.g. g++, clang++)
- **make**
- **libvips** (with C++ development files)
  - Ubuntu/Debian: `sudo apt install libvips-dev`
  - macOS: `brew install vips`

The single-header HTTP library **cpp-httplib** is vendored in this directory (`httplib.h`). No separate install for it.

## Build

```bash
make
```

This produces the `cpp_media` binary. If you see "libvips not found", install libvips as above and run `make` again.

## Run

```bash
./cpp_media [port]
```

Default port is **8080**. Example:

```bash
./cpp_media 8080
```

The server listens on `0.0.0.0` (all interfaces).

## Endpoints

### GET /health

Returns JSON:

```json
{ "status": "ok", "service": "cpp_media" }
```

Use for liveness/readiness checks.

### POST /process

Accepts an image and returns a thumbnail and optionally a resized/converted image.

**Input (one of):**

1. **Multipart form**  
   - `file`: image file (required)  
   - Optional: `thumbnail_size` (default 256), `resize_max` (default 1200), `output_format` (e.g. `jpg`, `png`), `operations` (e.g. `thumbnail,resize`).

2. **JSON body** (`Content-Type: application/json`)  
   - `image_base64`: base64-encoded image (required)  
   - Optional: `thumbnail_size`, `resize_max`, `output_format`, `operations` (same as above).

**Output (JSON):**

- `thumbnail_base64`, `thumbnail_content_type` (e.g. `image/jpeg`)
- `processed_base64`, `processed_content_type` (optional; present when resize is requested)

**Operations:** `thumbnail` generates a small square thumbnail; `resize` produces a version with the longest side capped at `resize_max`. Format conversion is applied to both (e.g. PNG input → JPG output when `output_format=jpg`).

## Clean

```bash
make clean
```

## Environment / port

Port is passed as the first argument (default **8080**). No other environment variables are required.

## Test instructions

With **cpp_media** running on port 8080, from repo root:

```bash
CPP_MEDIA_URL=http://localhost:8080 python_gen/.venv/bin/pytest contract_tests -v
```

See [docs/testing.md](../docs/testing.md) for contract and malformed input tests.

## Rails integration

Set `CPP_MEDIA_URL` (e.g. `http://localhost:8080`) in the Rails app. The generation job will POST the generated image to `CPP_MEDIA_URL/process` and attach the returned thumbnail (and optionally processed image) to the Asset.
