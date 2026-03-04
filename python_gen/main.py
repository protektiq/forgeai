"""
Python generation service (FastAPI + Pillow MVP).

Run: uvicorn main:app --host 0.0.0.0 --port 5000

Endpoints:
  GET  /health   -> { "status": "ok", "service": "python_gen" }
  POST /generate -> raw PNG (default) or JSON { image_base64, seed, model } when Accept: application/json
"""

import base64
import re
import secrets
from io import BytesIO

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

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
