"""
MinIO file synchronization for CoPaw Worker.
"""

import asyncio
import json
import os
import re
from pathlib import Path
from typing import Optional

from minio import Minio
from minio.error import S3Error
from rich.console import Console

console = Console()


class FileSync:
    """Handles bidirectional file sync between worker and MinIO."""

    def __init__(
        self,
        endpoint: str,
        access_key: str,
        secret_key: str,
        bucket: str,
        worker_name: str,
        secure: bool = False,
        local_dir: Optional[Path] = None,
    ):
        """
        Initialize file sync.

        Args:
            endpoint: MinIO endpoint (e.g., "fs-local.hiclaw.io:8080")
            access_key: MinIO access key
            secret_key: MinIO secret key
            bucket: MinIO bucket name
            worker_name: Worker name (used as prefix in bucket)
            secure: Use HTTPS
            local_dir: Local directory to sync (default: ~/.copaw-worker/<worker_name>)
        """
        # Parse endpoint - remove protocol if present
        self.endpoint = re.sub(r"^https?://", "", endpoint)
        self.access_key = access_key
        self.secret_key = secret_key
        self.bucket = bucket
        self.worker_name = worker_name
        self.secure = secure

        # Local directory
        self.local_dir = local_dir or Path.home() / ".copaw-worker" / worker_name
        self.local_dir.mkdir(parents=True, exist_ok=True)

        # MinIO client
        self.client = Minio(
            self.endpoint,
            access_key=access_key,
            secret_key=secret_key,
            secure=secure,
        )

        # Prefix for this worker in the bucket
        self.prefix = f"agents/{worker_name}/"

    def pull(self, exclude: Optional[set[str]] = None) -> list[str]:
        """
        Pull files from MinIO to local directory.

        Args:
            exclude: Set of filename patterns to exclude

        Returns:
            List of pulled file paths
        """
        exclude = exclude or set()
        pulled_files = []

        try:
            objects = self.client.list_objects(
                self.bucket,
                prefix=self.prefix,
                recursive=True,
            )

            for obj in objects:
                # Get relative path
                rel_path = obj.object_name[len(self.prefix) :]
                if not rel_path:
                    continue

                # Skip excluded files
                if any(
                    rel_path == excl or rel_path.startswith(f"{excl}/")
                    for excl in exclude
                ):
                    continue

                local_path = self.local_dir / rel_path
                local_path.parent.mkdir(parents=True, exist_ok=True)

                # Download file
                self.client.fget_object(self.bucket, obj.object_name, str(local_path))
                pulled_files.append(str(local_path))

        except S3Error as e:
            console.print(f"[red]MinIO pull error: {e}[/red]")
            raise

        return pulled_files

    def push(self, exclude: Optional[set[str]] = None) -> list[str]:
        """
        Push files from local directory to MinIO.

        Args:
            exclude: Set of filename patterns to exclude

        Returns:
            List of pushed file paths
        """
        exclude = exclude or {
            "openclaw.json",
            "AGENTS.md",
            "SOUL.md",
            ".agents",
            ".openclaw",
            ".cache",
            ".local",
            "__pycache__",
            ".git",
        }
        pushed_files = []

        if not self.local_dir.exists():
            return pushed_files

        try:
            for local_path in self.local_dir.rglob("*"):
                if not local_path.is_file():
                    continue

                rel_path = local_path.relative_to(self.local_dir)
                rel_str = str(rel_path)

                # Skip excluded files
                if any(
                    rel_str == excl
                    or rel_str.startswith(f"{excl}/")
                    or rel_str.startswith(f"{excl}\\")
                    for excl in exclude
                ):
                    continue

                # Skip hidden files
                if any(part.startswith(".") for part in rel_path.parts):
                    continue

                object_name = f"{self.prefix}{rel_str}"
                self.client.fput_object(
                    self.bucket,
                    object_name,
                    str(local_path),
                )
                pushed_files.append(str(local_path))

        except S3Error as e:
            console.print(f"[red]MinIO push error: {e}[/red]")
            raise

        return pushed_files

    def pull_shared(self) -> list[str]:
        """Pull shared files from MinIO."""
        shared_dir = self.local_dir.parent / "shared"
        shared_dir.mkdir(parents=True, exist_ok=True)
        pulled_files = []

        try:
            objects = self.client.list_objects(
                self.bucket,
                prefix="shared/",
                recursive=True,
            )

            for obj in objects:
                rel_path = obj.object_name[len("shared/") :]
                if not rel_path:
                    continue

                local_path = shared_dir / rel_path
                local_path.parent.mkdir(parents=True, exist_ok=True)

                self.client.fget_object(self.bucket, obj.object_name, str(local_path))
                pulled_files.append(str(local_path))

        except S3Error as e:
            console.print(f"[yellow]Warning: Could not pull shared files: {e}[/yellow]")

        return pulled_files

    def get_config(self) -> dict:
        """Pull and return the worker's openclaw.json config."""
        config_path = self.local_dir / "openclaw.json"

        try:
            self.client.fget_object(
                self.bucket,
                f"{self.prefix}openclaw.json",
                str(config_path),
            )
            with open(config_path) as f:
                return json.load(f)
        except S3Error:
            console.print("[red]Could not pull openclaw.json from MinIO[/red]")
            raise

    def get_soul(self) -> str:
        """Pull and return the worker's SOUL.md content."""
        soul_path = self.local_dir / "SOUL.md"

        try:
            self.client.fget_object(
                self.bucket,
                f"{self.prefix}SOUL.md",
                str(soul_path),
            )
            with open(soul_path) as f:
                return f.read()
        except S3Error:
            console.print("[red]Could not pull SOUL.md from MinIO[/red]")
            raise

    def get_agents_md(self) -> str:
        """Pull and return the worker's AGENTS.md content."""
        agents_path = self.local_dir / "AGENTS.md"

        try:
            self.client.fget_object(
                self.bucket,
                f"{self.prefix}AGENTS.md",
                str(agents_path),
            )
            with open(agents_path) as f:
                return f.read()
        except S3Error:
            console.print("[yellow]Could not pull AGENTS.md from MinIO[/yellow]")
            return ""


async def sync_loop(
    sync: FileSync,
    interval: int = 300,
    on_pull: Optional[callable] = None,
) -> None:
    """
    Run periodic sync loop.

    Args:
        sync: FileSync instance
        interval: Sync interval in seconds
        on_pull: Optional callback after pull
    """
    while True:
        await asyncio.sleep(interval)
        try:
            pulled = sync.pull()
            if pulled and on_pull:
                await on_pull(pulled)
        except Exception as e:
            console.print(f"[yellow]Sync error: {e}[/yellow]")
