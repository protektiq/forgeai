"""
Local model backend stub. Not wired to real models yet; use for testing the abstraction.
"""

from .base import BaseBackend, NormalizedResult


class LocalModelBackend(BaseBackend):
    """Stub for future local model (e.g. heavy ML). Raises until implemented."""

    BACKEND_ID = "local_model"
    MODEL_NAME = "local_model_stub"

    def generate(self, prompt: str) -> NormalizedResult:
        raise NotImplementedError(
            "local_model backend is not implemented; use GENERATOR_BACKEND=pillow_mock or "
            "workflow step config backend=pillow_mock"
        )
