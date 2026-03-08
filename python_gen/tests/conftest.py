"""
Pytest fixtures for Python gen contract and malformed tests.
Uses FastAPI TestClient/AsyncClient against the app (no live server required).
"""

import pytest
from httpx import ASGITransport, AsyncClient

# Import app after env is set so GENERATOR_BACKEND defaults apply
from main import app


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def client():
    """Async HTTP client against the FastAPI app via ASGI."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
