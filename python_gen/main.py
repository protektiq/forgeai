"""
Python generation service (FastAPI + pluggable backends).

Run: uvicorn main:app --host 0.0.0.0 --port 5000

Endpoints:
  GET  /health   -> { "status": "ok", "service": "python_gen" }
  POST /generate -> raw PNG (default) or JSON { image_base64, seed, model, backend, duration_ms } when Accept: application/json
"""

import base64
import json
import logging
import re
from contextvars import ContextVar
from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import Response, JSONResponse
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, Field

from backends import resolve_backend
from backends.base import NormalizedResult

# ---------------------------------------------------------------------------
# Structured logging: JSON lines with timestamp, service, level, correlation_id, message
# ---------------------------------------------------------------------------

CORRELATION_ID_CTX: ContextVar[str] = ContextVar("correlation_id", default="")


class JsonLogFormatter(logging.Formatter):
    """Emit one JSON object per log record with timestamp, service, level, correlation_id, message, and optional error_code."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "service": "python_gen",
            "level": record.levelname,
            "message": record.getMessage(),
        }
        cid = CORRELATION_ID_CTX.get()
        if cid:
            payload["correlation_id"] = cid
        if hasattr(record, "error_code") and record.error_code:
            payload["error_code"] = record.error_code
        return json.dumps(payload)


def configure_logging() -> None:
    logger = logging.getLogger("python_gen")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    handler = logging.StreamHandler()
    handler.setFormatter(JsonLogFormatter())
    logger.addHandler(handler)


configure_logging()
logger = logging.getLogger("python_gen")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

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
    backend: Optional[str] = Field(
        default=None,
        description="Override backend for this request (else GENERATOR_BACKEND env or pillow_mock).",
    )


class GenerateResponseJson(BaseModel):
    """JSON response when Accept: application/json. Normalized schema for all backends."""

    image_base64: str = Field(..., description="PNG image encoded as base64.")
    seed: int = Field(..., description="Seed used for generation.")
    model: str = Field(..., description="Model name (e.g. pillow-mvp).")
    backend: str = Field(..., description="Backend id that produced the image.")
    duration_ms: int = Field(..., description="Generation duration in milliseconds.")


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


def validate_prompt_no_control_chars(prompt: str) -> None:
    """Raise ValueError if prompt contains disallowed control characters."""
    if CONTROL_CHAR_PATTERN.search(prompt):
        raise ValueError("Prompt must not contain control characters")


def _result_to_response_json(result: NormalizedResult) -> GenerateResponseJson:
    """Convert NormalizedResult to JSON response model."""
    return GenerateResponseJson(
        image_base64=base64.b64encode(result.image_bytes).decode("ascii"),
        seed=result.seed,
        model=result.model,
        backend=result.backend,
        duration_ms=result.duration_ms,
    )


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Python Gen",
    description="Image generation service (pluggable backends; Pillow MVP default).",
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
    """Log X-Correlation-Id or X-Request-Id for request tracing; set context for structured logs."""
    correlation_id = (
        request.headers.get("X-Correlation-Id") or request.headers.get("X-Request-Id") or ""
    ).strip()
    token = CORRELATION_ID_CTX.set(correlation_id)
    try:
        if correlation_id:
            logger.info("request path=%s", request.url.path)
        response = await call_next(request)
        return response
    finally:
        CORRELATION_ID_CTX.reset(token)


@app.get("/health")
def health() -> dict[str, str]:
    """Health check for load balancers and runbooks."""
    return {"status": "ok", "service": "python_gen"}


@app.post("/generate", response_model=None)
def generate(request: Request, body: GenerateRequest) -> Response | GenerateResponseJson:
    """
    Generate an image for the given prompt.

    - Default: returns raw PNG bytes (Content-Type: image/png). Compatible with Rails worker.
    - If Accept header is application/json: returns JSON { image_base64, seed, model, backend, duration_ms }.
    """
    try:
        validate_prompt_no_control_chars(body.prompt)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e)) from e

    try:
        backend_instance = resolve_backend(body.backend)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    try:
        result = backend_instance.generate(body.prompt)
    except NotImplementedError as e:
        raise HTTPException(status_code=501, detail=str(e)) from e

    accept = (request.headers.get("Accept") or "").strip().lower()
    if "application/json" in accept:
        return _result_to_response_json(result)

    return Response(
        content=result.image_bytes,
        media_type="image/png",
        headers={"Content-Disposition": 'inline; filename="generated.png"'},
    )


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
