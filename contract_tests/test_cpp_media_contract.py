"""
Contract tests for C++ media service.
Aligns with docs/contracts/cpp_media.yaml: GET /health, POST /process (valid body).
"""

import pytest
import httpx


def test_health_returns_ok_and_service_name(cpp_media_url):
    """GET /health returns 200 with status and service."""
    response = httpx.get(f"{cpp_media_url}/health", timeout=5.0)
    assert response.status_code == 200
    data = response.json()
    assert data.get("status") == "ok"
    assert data.get("service") == "cpp_media"


def test_process_json_returns_thumbnail_and_profile_used(cpp_media_url, minimal_png_base64):
    """POST /process with JSON body (image_base64) returns 200 and thumbnail_base64, profile_used."""
    response = httpx.post(
        f"{cpp_media_url}/process",
        json={"image_base64": minimal_png_base64},
        headers={"Content-Type": "application/json"},
        timeout=10.0,
    )
    assert response.status_code == 200
    data = response.json()
    assert "thumbnail_base64" in data
    assert "thumbnail_content_type" in data
    assert "profile_used" in data
    assert isinstance(data["thumbnail_base64"], str)
    assert len(data["thumbnail_base64"]) > 0
