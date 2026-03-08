"""
Contract tests for Python gen service.
Aligns with docs/contracts/python_gen.yaml: GET /health, POST /generate (valid body).
"""

import pytest


@pytest.mark.asyncio
async def test_health_returns_ok_and_service_name(client):
    """GET /health returns 200 with status and service."""
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data.get("status") == "ok"
    assert data.get("service") == "python_gen"


@pytest.mark.asyncio
async def test_generate_returns_png_by_default(client):
    """POST /generate with valid body returns 200 and image/png when Accept is not application/json."""
    response = await client.post(
        "/generate",
        json={"prompt": "a red circle"},
        headers={"Accept": "image/png"},
    )
    assert response.status_code == 200
    assert response.headers.get("content-type", "").startswith("image/png")
    assert len(response.content) > 0


@pytest.mark.asyncio
async def test_generate_returns_json_when_accept_json(client):
    """POST /generate with Accept: application/json returns JSON with image_base64, seed, model, backend, duration_ms."""
    response = await client.post(
        "/generate",
        json={"prompt": "a blue square"},
        headers={"Accept": "application/json"},
    )
    assert response.status_code == 200
    assert response.headers.get("content-type", "").startswith("application/json")
    data = response.json()
    assert "image_base64" in data
    assert "seed" in data
    assert "model" in data
    assert "backend" in data
    assert "duration_ms" in data
    assert isinstance(data["seed"], int)
    assert isinstance(data["duration_ms"], int)
