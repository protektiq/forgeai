# C++ media

HTTP service for image processing: thumbnail, resize, format conversion (using libvips). Used by the Rails worker when `CPP_MEDIA_URL` is set; the worker attaches the returned thumbnail and processed outputs to the Asset.

## Port

Default: **8080**. Override by passing port as first command-line argument, e.g. `./server 9000`.

## Processing profiles

Named presets control thumbnail size, resize max, format, and quality:

- **thumbnail_square**: Square thumbnail only (256px, jpg). No resized output.
- **web_optimized**: Thumbnail + resize to max 1200px, jpg Q=85. Default when no profile is sent.
- **high_quality_jpg**: Thumbnail + resize to max 2400px, jpg Q=92.

If `profile` is omitted or unknown, `web_optimized` is used. Optional overrides (e.g. `resize_max`, `quality`) are applied on top of the profile.

## Endpoints

### GET /health

Health check.

- **Response**: **200** `{ "status": "ok", "service": "cpp_media" }`

### POST /process

Process an image: produce thumbnail and optionally resized/format-converted image.

**Request (JSON)** — used by Rails worker

- **Content-Type**: `application/json`
- **Body**:
  - `image_base64`: Required. Base64-encoded image bytes.
  - `profile`: Optional string. One of `thumbnail_square`, `web_optimized`, `high_quality_jpg`. If absent, defaults to `web_optimized`.
  - Overrides (optional): `thumbnail_size`, `resize_max`, `width`, `height`, `quality`, `output_format`, `operations`. Applied on top of profile.

**Request (multipart)** — alternative

- **Content-Type**: `multipart/form-data`
- **Field**: `file` — image file.
- Optional: `profile`, `thumbnail_size`, `resize_max`, `width`, `height`, `quality`, `output_format`, `operations`.

**Response (success)**

- **200** `{ "thumbnail_base64", "thumbnail_content_type", "processed_base64?", "processed_content_type?", "profile_used" }`
  - `profile_used`: Profile name applied (e.g. `web_optimized`).
  - `thumbnail_*` present when thumbnail was requested.
  - `processed_*` present when resize was requested and successful.

**Errors**

- **400** — Missing or invalid input (e.g. no `image_base64`/file, invalid JSON, empty/invalid base64).
- **422** — Image processing failed (e.g. libvips error).

## Rails worker contract

When `CPP_MEDIA_URL` is set, the worker sends a **profile** (e.g. `web_optimized`, `thumbnail_square`) and attaches both thumbnail and processed output (when present) to the Asset with metadata indicating the profile.

## Optional headers

- **X-Correlation-Id** / **X-Request-Id**: Logged for request tracing.
