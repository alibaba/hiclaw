"""
Configuration management for CoPaw Worker.

Bootstrap flow:
1. User provides only MinIO credentials (endpoint, access_key, secret_key)
2. Worker pulls openclaw.json from MinIO
3. openclaw.json contains Matrix, AI Gateway, and other config
"""

from pathlib import Path
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class WorkerConfig(BaseSettings):
    """
    Worker configuration.

    Only MinIO credentials are required at startup.
    All other config is pulled from MinIO's openclaw.json.
    """

    model_config = SettingsConfigDict(
        env_prefix="HICLAW_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Required: Worker identity
    worker_name: str = Field(..., description="Unique worker name")

    # Required: MinIO credentials (bootstrap only)
    minio_endpoint: str = Field(..., description="MinIO endpoint URL")
    minio_access_key: str = Field(..., description="MinIO access key")
    minio_secret_key: str = Field(..., description="MinIO secret key")
    minio_bucket: str = Field(
        default="hiclaw-storage",
        description="MinIO bucket name",
    )
    minio_secure: bool = Field(
        default=False,
        description="Use HTTPS for MinIO connection",
    )

    # Optional: Override config from openclaw.json
    matrix_server: Optional[str] = Field(
        default=None,
        description="Override Matrix homeserver URL",
    )
    matrix_user: Optional[str] = Field(
        default=None,
        description="Override Matrix username (defaults to worker_name)",
    )
    matrix_password: Optional[str] = Field(
        default=None,
        description="Override Matrix password",
    )
    ai_gateway: Optional[str] = Field(
        default=None,
        description="Override AI Gateway URL",
    )
    gateway_token: Optional[str] = Field(
        default=None,
        description="Override Gateway authentication token",
    )

    # Runtime settings
    install_dir: Path = Field(
        default_factory=lambda: Path.home() / ".copaw-worker",
        description="Installation directory for worker files",
    )
    model: str = Field(
        default="qwen3.5-plus",
        description="LLM model to use",
    )
    skills_api_url: Optional[str] = Field(
        default=None,
        description="Skills API URL for skill discovery",
    )
    log_level: str = Field(default="INFO", description="Logging level")
    sync_interval: int = Field(default=300, description="File sync interval in seconds")


def load_config() -> WorkerConfig:
    """Load and validate worker configuration."""
    return WorkerConfig()
