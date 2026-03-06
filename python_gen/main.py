"""
Python generation service (FastAPI + Pillow MVP).

Run: uvicorn main:app --host 0.0.0.0 --port 5000

Endpoints:
  GET  /health   -> { "status": "ok", "service": "python_gen" }
  POST /generate -> raw PNG (default) or JSON { image_base64, seed, model } when Accept: application/json
"""

import base64
import logging
import re
import secrets
from io import BytesIO

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import Response, JSONResponse
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("python_gen")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MODEL_NAME = "pillow-mvp"
IMAGE_SIZE = 512
PROMPT_MAX_LENGTH = 10_000
# Control chars and other characters we reject in prompt (basic sanitization)
CONTROL_CHAR_PATTERN = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------


class GenerateRequest(BaseModel):
    """Request body for POST /generate."""

    prompt: str = Field(
        ...,
        min_length=1,
        max_length=PROMPT_MAX_LENGTH,
        description="Text prompt for image generation.",
    )


class GenerateResponseJson(BaseModel):
    """JSON response when Accept: application/json."""

    image_base64: str = Field(..., description="PNG image encoded as base64.")
    seed: int = Field(..., description="Seed used for generation.")
    model: str = Field(..., description="Model name (e.g. pillow-mvp).")


# Standard error response shape (see docs/contracts/error-response.md)
class ErrorPart(BaseModel):
    code: str
    message: str
    correlation_id: str


class ApiErrorResponse(BaseModel):
    error: ErrorPart


def _status_to_code(status_code: int) -> str:
    """Map HTTP status code to standard error code."""
    if status_code == 400:
        return "invalid_request"
    if status_code == 401:
        return "unauthorized"
    if status_code == 404:
        return "not_found"
    if status_code == 422:
        return "validation_error"
    if status_code == 429:
        return "rate_limit_exceeded"
    if status_code == 502:
        return "bad_gateway"
    if status_code == 503:
        return "service_unavailable"
    if status_code >= 500:
        return "internal_error"
    return "invalid_request"


# ---------------------------------------------------------------------------
# Image generation (Pillow placeholder)
# ---------------------------------------------------------------------------

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    Image = None  # type: ignore
    ImageDraw = None  # type: ignore
    ImageFont = None  # type: ignore


def generate_placeholder_png(prompt: str, seed: int) -> bytes:
    """
    Create a placeholder image with the prompt text drawn on it.
    Returns PNG bytes.
    """
    if Image is None or ImageDraw is None or ImageFont is None:
        raise RuntimeError("Pillow (PIL) is not installed")

    img = Image.new("RGB", (IMAGE_SIZE, IMAGE_SIZE), color=(240, 240, 245))
    draw = ImageDraw.Draw(img)

    # Try a default font; fall back to default if no TTF available
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
    except (OSError, IOError):
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 24)
        except (OSError, IOError):
            font = ImageFont.load_default()

    # Simple text wrap: split into lines that fit width (approximate char width 14)
    max_chars_per_line = (IMAGE_SIZE - 40) // 14
    lines: list[str] = []
    words = prompt.split()
    current_line: list[str] = []
    current_len = 0
    for w in words:
        if current_len + len(w) + 1 <= max_chars_per_line:
            current_line.append(w)
            current_len += len(w) + 1
        else:
            if current_line:
                lines.append(" ".join(current_line))
            current_line = [w]
            current_len = len(w)
    if current_line:
        lines.append(" ".join(current_line))

    if not lines:
        lines = [prompt[:max_chars_per_line]]

    line_height = 32
    total_height = len(lines) * line_height
    y_start = max(20, (IMAGE_SIZE - total_height) // 2)
    for i, line in enumerate(lines):
        # Approximate text bbox for centering (left-aligned block, centered vertically)
        bbox = draw.textbbox((0, 0), line, font=font)
        text_width = bbox[2] - bbox[0]
        x = (IMAGE_SIZE - text_width) // 2
        y = y_start + i * line_height
        draw.text((x, y), line, fill=(40, 40, 50), font=font)

    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def validate_prompt_no_control_chars(prompt: str) -> None:
    """Raise ValueError if prompt contains disallowed control characters."""
    if CONTROL_CHAR_PATTERN.search(prompt):
        raise ValueError("Prompt must not contain control characters")


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Python Gen",
    description="Image generation service (Pillow placeholder MVP).",
    version="0.1.0",
)


def _get_correlation_id(request: Request) -> str:
    """Read correlation id from headers or return empty string."""
    return (
        (request.headers.get("X-Correlation-Id") or request.headers.get("X-Request-Id") or "").strip()
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    """Format HTTPException as standard error shape with correlation_id."""
    correlation_id = _get_correlation_id(request)
    detail = exc.detail
    if isinstance(detail, dict):
        message = detail.get("msg", detail.get("message", str(detail)))
    else:
        message = str(detail)
    code = _status_to_code(exc.status_code)
    body = ApiErrorResponse(error=ErrorPart(code=code, message=message, correlation_id=correlation_id))
    return JSONResponse(
        status_code=exc.status_code,
        content=body.model_dump(),
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Format validation errors as standard error shape with correlation_id."""
    correlation_id = _get_correlation_id(request)
    messages = []
    for err in exc.errors():
        loc = ".".join(str(x) for x in (err.get("loc") or []) if x != "body")
        msg = err.get("msg", "validation error")
        if loc:
            messages.append(f"{loc}: {msg}")
        else:
            messages.append(msg)
    message = "; ".join(messages) if messages else "Validation error"
    body = ApiErrorResponse(
        error=ErrorPart(code="validation_error", message=message, correlation_id=correlation_id)
    )
    return JSONResponse(status_code=422, content=body.model_dump())


@app.middleware("http")
async def log_correlation_id(request: Request, call_next):
    """Log X-Correlation-Id or X-Request-Id for request tracing."""
    correlation_id = (
        request.headers.get("X-Correlation-Id") or request.headers.get("X-Request-Id") or ""
    )
    if correlation_id:
        logger.info("python_gen request correlation_id=%s path=%s", correlation_id, request.url.path)
    response = await call_next(request)
    return response


@app.get("/health")
def health() -> dict[str, str]:
    """Health check for load balancers and runbooks."""
    return {"status": "ok", "service": "python_gen"}


@app.post("/generate", response_model=None)
def generate(request: Request, body: GenerateRequest) -> Response | GenerateResponseJson:
    """
    Generate an image for the given prompt.

    - Default: returns raw PNG bytes (Content-Type: image/png). Compatible with Rails worker.
    - If Accept header is application/json: returns JSON { image_base64, seed, model }.
    """
    try:
        validate_prompt_no_control_chars(body.prompt)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e)) from e
    seed = secrets.randbelow(2**31)
    png_bytes = generate_placeholder_png(body.prompt, seed)

    accept = (request.headers.get("Accept") or "").strip().lower()
    if "application/json" in accept:
        return GenerateResponseJson(
            image_base64=base64.b64encode(png_bytes).decode("ascii"),
            seed=seed,
            model=MODEL_NAME,
        )

    return Response(
        content=png_bytes,
        media_type="image/png",
        headers={"Content-Disposition": 'inline; filename="generated.png"'},
    )


# Optional: keep a simple root for quick checks (not required by plan)
@app.get("/")
def index() -> dict[str, str]:
    """Root route; points to health and generate."""
    return {
        "service": "python_gen",
        "docs": "/docs",
        "health": "/health",
        "generate": "POST /generate",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=5000, reload=False)
