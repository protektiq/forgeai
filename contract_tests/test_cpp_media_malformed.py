"""
Malformed input tests for C++ media service.
Ensures invalid /process requests return 400 with error.code (e.g. invalid_request).
"""

import pytest
import httpx


def test_process_empty_body_returns_400(cpp_media_url):
    """POST /process with empty body returns 400."""
    response = httpx.post(
        f"{cpp_media_url}/process",
        content=b"",
        headers={"Content-Type": "application/json"},
        timeout=5.0,
    )
    assert response.status_code == 400
    data = response.json()
    assert "error" in data
    assert data.get("error", {}).get("code") == "invalid_request"


def test_process_json_without_image_base64_returns_400(cpp_media_url):
    """POST /process with JSON body missing image_base64 returns 400."""
    response = httpx.post(
        f"{cpp_media_url}/process",
        json={"profile": "web_optimized"},
        headers={"Content-Type": "application/json"},
        timeout=5.0,
    )
    assert response.status_code == 400
    data = response.json()
    assert data.get("error", {}).get("code") == "invalid_request"


def test_process_json_empty_image_base64_returns_400(cpp_media_url):
    """POST /process with empty image_base64 returns 400."""
    response = httpx.post(
        f"{cpp_media_url}/process",
        json={"image_base64": ""},
        headers={"Content-Type": "application/json"},
        timeout=5.0,
    )
    assert response.status_code == 400
    data = response.json()
    assert data.get("error", {}).get("code") == "invalid_request"


def test_process_json_invalid_base64_returns_400(cpp_media_url):
    """POST /process with invalid base64 in image_base64 returns 400 or 422 (rejected)."""
    response = httpx.post(
        f"{cpp_media_url}/process",
        json={"image_base64": "not-valid-base64!!"},
        headers={"Content-Type": "application/json"},
        timeout=5.0,
    )
    # Parser may return 400 (invalid/empty base64) or 422 (decode yields non-image bytes)
    assert response.status_code in (400, 422)
    data = response.json()
    assert data.get("error", {}).get("code") in ("invalid_request", "validation_error")


def test_process_wrong_content_type_no_file_returns_400(cpp_media_url):
    """POST /process with Content-Type other than application/json and no multipart file returns 400."""
    response = httpx.post(
        f"{cpp_media_url}/process",
        content=b"plain text",
        headers={"Content-Type": "text/plain"},
        timeout=5.0,
    )
    assert response.status_code == 400
    data = response.json()
    assert data.get("error", {}).get("code") == "invalid_request"
