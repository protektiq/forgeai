# C++ media

HTTP service for image processing: thumbnail, resize, format conversion (using libvips). Used by the Rails worker when `CPP_MEDIA_URL` is set; the worker attaches the returned thumbnail to the Asset.

## Port

Default: **8080**. Override by passing port as first command-line argument, e.g. `./server 9000`.

## Endpoints

### GET /health

Health check.

- **Response**: **200** `{ "status": "ok", "service": "cpp_media" }`

### POST /process

Process an image: produce thumbnail and optionally resized/format-converted image.

**Request (JSON)** — used by Rails worker

- **Content-Type**: `application/json`
- **Body**: `{ "image_base64": "<base64 image data>", "thumbnail_size?", "resize_max?", "output_format?", "operations?" }`
  - `image_base64`: Required. Base64-encoded image bytes.
  - `thumbnail_size`: Optional int; default 256. Max side for thumbnail.
  - `resize_max`: Optional int; default 1200. Max side for processed image.
  - `output_format`: Optional string; default `"jpg"` (e.g. `"jpg"`, `"png"`).
  - `operations`: Optional string; default `"thumbnail,resize"`. Comma-separated; include `"thumbnail"` and/or `"resize"`. If neither, both are enabled.

**Request (multipart)** — alternative

- **Content-Type**: `multipart/form-data`
- **Field**: `file` — image file.
- Optional fields: `thumbnail_size`, `resize_max`, `output_format`, `operations` (same meaning as JSON).

**Response (success)**

- **200** `{ "thumbnail_base64": "<base64>", "thumbnail_content_type": "image/jpeg" | "image/png", "processed_base64?", "processed_content_type?" }`
  - `thumbnail_base64` and `thumbnail_content_type` are always present when thumbnail was requested.
  - `processed_base64` and `processed_content_type` are present when resize was requested and successful.

**Errors**

- **400** — Missing or invalid input (e.g. no `image_base64`/file, invalid JSON, empty/invalid base64). Body: `{ "error": "..." }`.
- **422** — Image processing failed (e.g. libvips error). Body: `{ "error": "..." }`.

## Rails worker contract

When `CPP_MEDIA_URL` is set, the worker (GenerateAssetJob) sends:

- **Method**: POST
- **URL**: `{CPP_MEDIA_URL}/process`
- **Headers**: `Content-Type: application/json`, `Accept: application/json`, `X-Correlation-Id` (when available)
- **Body**: `{ "image_base64", "thumbnail_size": 256, "resize_max": 1200, "output_format": "jpg", "operations": "thumbnail,resize" }`

The worker requires in the response:

- `thumbnail_base64` (string)
- `thumbnail_content_type` (string, must be `image/jpeg` or `image/png`)

Optional `processed_base64` / `processed_content_type` are not stored by the worker; only the thumbnail is attached to the Asset.

## Optional headers

- **X-Correlation-Id** / **X-Request-Id**: Logged for request tracing.
