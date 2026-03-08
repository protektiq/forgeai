"""
Base contract for generation backends.

All backends must return a NormalizedResult so the API can return a consistent
JSON schema: image_base64, seed, model, backend, duration_ms.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class NormalizedResult:
    """Result every backend must return. Maps to JSON response schema."""

    image_bytes: bytes
    seed: int
    model: str
    backend: str
    duration_ms: int


class BaseBackend(ABC):
    """Abstract base for generation backends. All backends must implement generate()."""

    @abstractmethod
    def generate(self, prompt: str) -> NormalizedResult:
        """
        Generate an image for the given prompt.

        All backends must return a NormalizedResult with image_bytes, seed,
        model, backend, and duration_ms so the API can return a consistent schema.
        """
        ...
