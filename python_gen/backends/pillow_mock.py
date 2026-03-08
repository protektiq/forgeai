"""
Pillow placeholder backend (MVP). Draws prompt text on a solid image.
"""

import secrets
import time
from io import BytesIO

from .base import BaseBackend, NormalizedResult

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    Image = None  # type: ignore
    ImageDraw = None  # type: ignore
    ImageFont = None  # type: ignore

IMAGE_SIZE = 512


def _generate_placeholder_png(prompt: str, seed: int) -> bytes:
    """Create a placeholder image with the prompt text drawn on it. Returns PNG bytes."""
    if Image is None or ImageDraw is None or ImageFont is None:
        raise RuntimeError("Pillow (PIL) is not installed")

    img = Image.new("RGB", (IMAGE_SIZE, IMAGE_SIZE), color=(240, 240, 245))
    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
    except (OSError, IOError):
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 24)
        except (OSError, IOError):
            font = ImageFont.load_default()

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
        bbox = draw.textbbox((0, 0), line, font=font)
        text_width = bbox[2] - bbox[0]
        x = (IMAGE_SIZE - text_width) // 2
        y = y_start + i * line_height
        draw.text((x, y), line, fill=(40, 40, 50), font=font)

    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


class PillowMockBackend(BaseBackend):
    """Pillow MVP backend: placeholder image with prompt text."""

    BACKEND_ID = "pillow_mock"
    MODEL_NAME = "pillow-mvp"

    def generate(self, prompt: str) -> NormalizedResult:
        seed = secrets.randbelow(2**31)
        t0 = time.perf_counter()
        png_bytes = _generate_placeholder_png(prompt, seed)
        duration_ms = int((time.perf_counter() - t0) * 1000)
        return NormalizedResult(
            image_bytes=png_bytes,
            seed=seed,
            model=self.MODEL_NAME,
            backend=self.BACKEND_ID,
            duration_ms=duration_ms,
        )
