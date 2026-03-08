"""
Malformed input tests for Python gen service.
Ensures invalid prompts and bodies are rejected with expected status and error.code.
"""

import pytest

PROMPT_MAX_LENGTH = 10_000


@pytest.mark.asyncio
async def test_generate_missing_prompt_returns_422(client):
    """POST /generate without prompt returns 422 validation_error."""
    response = await client.post("/generate", json={})
    assert response.status_code == 422
    data = response.json()
    assert data.get("error", {}).get("code") == "validation_error"


@pytest.mark.asyncio
async def test_generate_empty_prompt_returns_422(client):
    """POST /generate with empty string prompt returns 422."""
    response = await client.post("/generate", json={"prompt": ""})
    assert response.status_code == 422
    data = response.json()
    assert data.get("error", {}).get("code") == "validation_error"


@pytest.mark.asyncio
async def test_generate_prompt_too_long_returns_422(client):
    """POST /generate with prompt longer than 10000 chars returns 422."""
    long_prompt = "x" * (PROMPT_MAX_LENGTH + 1)
    response = await client.post("/generate", json={"prompt": long_prompt})
    assert response.status_code == 422
    data = response.json()
    assert data.get("error", {}).get("code") == "validation_error"


@pytest.mark.asyncio
async def test_generate_prompt_with_control_chars_returns_422(client):
    """POST /generate with control characters in prompt returns 422."""
    response = await client.post("/generate", json={"prompt": "normal\x00null"})
    assert response.status_code == 422
    data = response.json()
    # App raises HTTPException(422) for control chars
    assert "error" in data
    assert data.get("error", {}).get("code") in ("validation_error", "invalid_request")


@pytest.mark.asyncio
async def test_generate_non_string_prompt_returns_422(client):
    """POST /generate with non-string prompt (e.g. number) returns 422."""
    response = await client.post("/generate", json={"prompt": 12345})
    assert response.status_code == 422
    data = response.json()
    assert data.get("error", {}).get("code") == "validation_error"
