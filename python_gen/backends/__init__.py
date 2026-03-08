"""
Backend registry and resolution. All backends must return NormalizedResult.
"""

import os
from typing import Optional

from .base import BaseBackend, NormalizedResult
from .local_model import LocalModelBackend
from .pillow_mock import PillowMockBackend
from .test_stub import TestStubBackend

DEFAULT_BACKEND_ID = "pillow_mock"

_REGISTRY: dict[str, type[BaseBackend]] = {
    PillowMockBackend.BACKEND_ID: PillowMockBackend,
    LocalModelBackend.BACKEND_ID: LocalModelBackend,
    TestStubBackend.BACKEND_ID: TestStubBackend,
}


def get_registry() -> dict[str, type[BaseBackend]]:
    """Return the backend id -> class mapping (read-only)."""
    return dict(_REGISTRY)


def resolve_backend(backend_id: Optional[str] = None) -> BaseBackend:
    """
    Resolve backend: backend_id (if non-empty) -> GENERATOR_BACKEND env -> default.

    Raises ValueError if backend_id is unknown.
    """
    effective = (
        (backend_id or "").strip()
        or os.environ.get("GENERATOR_BACKEND", "").strip()
        or DEFAULT_BACKEND_ID
    )
    if not effective:
        effective = DEFAULT_BACKEND_ID
    if effective not in _REGISTRY:
        raise ValueError(
            f"Unknown generator backend: {effective!r}. "
            f"Known: {sorted(_REGISTRY.keys())}"
        )
    return _REGISTRY[effective]()


__all__ = [
    "BaseBackend",
    "NormalizedResult",
    "DEFAULT_BACKEND_ID",
    "get_registry",
    "resolve_backend",
]
