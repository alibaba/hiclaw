"""
CoPaw Worker - Lightweight HiClaw Worker runtime.
"""

__version__ = "0.1.0"

from copaw_worker.worker import Worker
from copaw_worker.config import WorkerConfig

__all__ = ["Worker", "WorkerConfig", "__version__"]
