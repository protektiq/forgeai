"""
Contract and malformed tests for C++ media service (POST /process, GET /health).
Run against a running cpp_media binary (default http://localhost:8080).
Set CPP_MEDIA_URL to override. Requires: pip install pytest httpx
"""

import os

import pytest

# Base URL for cpp_media (must be running)
CPP_MEDIA_URL = os.environ.get("CPP_MEDIA_URL", "http://localhost:8080")

# Minimal 1x1 PNG (valid image for /process)
MINIMAL_PNG_BASE64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


@pytest.fixture
def cpp_media_url():
    return CPP_MEDIA_URL.rstrip("/")


@pytest.fixture
def minimal_png_base64():
    return MINIMAL_PNG_BASE64
