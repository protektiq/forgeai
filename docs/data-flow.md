# Data flow

This diagram is updated as the project evolves. Rails is the system of record and the user-facing product.

```mermaid
flowchart LR
  subgraph users [User]
    Browser[Browser]
  end
  subgraph rails [Rails app - system of record]
    Auth[Devise auth]
    Dashboard[Dashboard]
    DB[(SQLite DB)]
    JobQueue[Sidekiq]
    Worker[GenerateAssetJob]
    Assets[Asset library]
  end
  subgraph external [External services]
    PythonGen[Python gen]
    CppMedia[C++ media]
    RustIndex[Rust index]
  end
  Browser -->|sign in / sign up / sign out| Auth
  Browser -->|"Generate" prompt| Dashboard
  Dashboard -->|create GenerationJob queued| DB
  Dashboard -->|perform_later| JobQueue
  JobQueue --> Worker
  Worker -->|status running| DB
  Worker -->|POST /generate Accept application/json| PythonGen
  Worker -->|store file, create Asset with generator_metadata| DB
  Worker -->|POST /process with image JSON| CppMedia
  CppMedia -->|JSON thumbnail_base64 etc| Worker
  Worker -->|attach thumbnail to Asset| DB
  Worker -->|POST /index asset_id prompt metadata| RustIndex
  Worker -->|status completed or failed| DB
  Browser -->|list / view assets, GET /search?q=...| Assets
  Assets -->|GET /search?q=...| RustIndex
  Assets -->|read Asset file and thumbnail, GenerationJob| DB
```

**Current state:** Users log in via Devise and submit prompts on the dashboard. A `GenerationJob` is created with status `queued` and `GenerateAssetJob` is enqueued in Sidekiq (Redis). The worker marks the job `running`, calls the Python generator service (HTTP POST to `/generate` with `Accept: application/json`), receives JSON `{ image_base64, seed, model }`, decodes the image, stores it in Active Storage, creates an `Asset` with generator_metadata (seed, model) in the Asset’s `metadata` column. If `CPP_MEDIA_URL` is set, the worker POSTs the image to the C++ media service at `/process` (JSON with image_base64 and options); cpp_media returns JSON with `thumbnail_base64` and `thumbnail_content_type`; the worker attaches the thumbnail to the Asset. If `CPP_MEDIA_URL` is not set but `MEDIA_SERVICE_COMMAND` is set, the worker runs the C++ media command (CLI) with env `INPUT_PATH`, `ASSET_ID`, `PROMPT` (no thumbnail attachment). The worker then optionally calls the Rust index service: when `INDEX_SERVICE_URL` is set it POSTs to `/index` with JSON `{ asset_id, prompt, metadata, tags }`; when only `INDEX_SERVICE_COMMAND` is set it runs the CLI with env `ASSET_ID`, `PROMPT`. The job is marked `completed` or `failed` with `error_message`. Job statuses: queued → running → completed | failed. The asset library and asset detail pages read each Asset’s `file` and `thumbnail` from Active Storage; thumbnails are displayed when present. When `INDEX_SERVICE_URL` is set, the asset library includes a search box; submitting a query sends GET `/search?q=...` to the Rust index service, and the list is filtered to the returned asset IDs (scoped to the current user).
