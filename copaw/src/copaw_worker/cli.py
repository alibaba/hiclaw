"""
CLI entry point for CoPaw Worker.
"""

import asyncio
import signal
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.panel import Panel

from copaw_worker import __version__
from copaw_worker.worker import Worker
from copaw_worker.config import WorkerConfig

app = typer.Typer(
    name="copaw-worker",
    help="Lightweight HiClaw Worker runtime based on AgentScope",
)
console = Console()


def version_callback(value: bool) -> None:
    """Show version and exit."""
    if value:
        console.print(f"copaw-worker version {__version__}")
        raise typer.Exit()


@app.callback()
def callback(
    version: bool = typer.Option(
        False,
        "--version",
        "-v",
        callback=version_callback,
        is_eager=True,
        help="Show version and exit",
    ),
) -> None:
    """CoPaw Worker - Lightweight HiClaw Worker runtime."""


@app.command()
def run(
    # Required: Worker identity and MinIO (bootstrap)
    worker_name: str = typer.Option(
        ...,
        "--worker-name",
        "-n",
        envvar="HICLAW_WORKER_NAME",
        help="Worker name",
    ),
    # MinIO (required - all other config comes from openclaw.json)
    minio_endpoint: str = typer.Option(
        ...,
        "--minio-endpoint",
        envvar="HICLAW_MINIO_ENDPOINT",
        help="MinIO endpoint URL",
    ),
    minio_access_key: str = typer.Option(
        ...,
        "--minio-access-key",
        envvar="HICLAW_MINIO_ACCESS_KEY",
        help="MinIO access key",
    ),
    minio_secret_key: str = typer.Option(
        ...,
        "--minio-secret-key",
        envvar="HICLAW_MINIO_SECRET_KEY",
        help="MinIO secret key",
    ),
    # Optional overrides (pulled from openclaw.json by default)
    matrix_server: Optional[str] = typer.Option(
        None,
        "--matrix-server",
        envvar="HICLAW_MATRIX_SERVER",
        help="Matrix homeserver URL (override)",
    ),
    matrix_user: Optional[str] = typer.Option(
        None,
        "--matrix-user",
        envvar="HICLAW_MATRIX_USER",
        help="Matrix username (defaults to worker_name)",
    ),
    matrix_password: Optional[str] = typer.Option(
        None,
        "--matrix-password",
        envvar="HICLAW_MATRIX_PASSWORD",
        help="Matrix password (only needed if not using token)",
    ),
    ai_gateway: Optional[str] = typer.Option(
        None,
        "--ai-gateway",
        envvar="HICLAW_AI_GATEWAY",
        help="AI Gateway URL (override)",
    ),
    gateway_token: Optional[str] = typer.Option(
        None,
        "--gateway-token",
        envvar="HICLAW_GATEWAY_TOKEN",
        help="Gateway authentication token (override)",
    ),
    minio_bucket: str = typer.Option(
        "hiclaw-storage",
        "--minio-bucket",
        envvar="HICLAW_MINIO_BUCKET",
        help="MinIO bucket name",
    ),
    install_dir: Path = typer.Option(
        None,
        "--install-dir",
        envvar="HICLAW_INSTALL_DIR",
        help="Installation directory",
    ),
    model: str = typer.Option(
        "qwen3.5-plus",
        "--model",
        envvar="HICLAW_MODEL",
        help="LLM model to use",
    ),
) -> None:
    """
    Start the CoPaw Worker agent.

    Only MinIO credentials are required. All other config (Matrix, AI Gateway)
    is pulled from openclaw.json in MinIO.
    """
    console.print(
        Panel.fit(
            f"[bold green]CoPaw Worker v{__version__}[/bold green]\n"
            f"Worker: [cyan]{worker_name}[/cyan]",
            title="Starting Worker",
        )
    )

    # Build config (optional params will be None if not provided)
    config = WorkerConfig(
        worker_name=worker_name,
        matrix_server=matrix_server or "",
        matrix_user=matrix_user or "",
        matrix_password=matrix_password or "",
        ai_gateway=ai_gateway or "",
        gateway_token=gateway_token or "",
        minio_endpoint=minio_endpoint,
        minio_access_key=minio_access_key,
        minio_secret_key=minio_secret_key,
        minio_bucket=minio_bucket,
        install_dir=install_dir or Path.home() / ".copaw-worker",
        model=model,
    )

    # Create worker
    worker = Worker(config)

    # Set up signal handlers
    loop = asyncio.get_event_loop()

    def handle_signal():
        console.print("\n[yellow]Received shutdown signal...[/yellow]")
        asyncio.create_task(worker.stop())

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_signal)

    # Run worker
    try:
        asyncio.run(worker.run())
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted by user.[/yellow]")


@app.command()
def sync(
    worker_name: str = typer.Option(
        ...,
        "--worker-name",
        "-n",
        help="Worker name",
    ),
    minio_endpoint: str = typer.Option(
        ...,
        "--minio-endpoint",
        help="MinIO endpoint URL",
    ),
    minio_access_key: str = typer.Option(
        ...,
        "--minio-access-key",
        help="MinIO access key",
    ),
    minio_secret_key: str = typer.Option(
        ...,
        "--minio-secret-key",
        help="MinIO secret key",
    ),
    minio_bucket: str = typer.Option(
        "hiclaw-storage",
        "--minio-bucket",
        help="MinIO bucket name",
    ),
    direction: str = typer.Option(
        "pull",
        "--direction",
        "-d",
        help="Sync direction: pull (default) or push",
    ),
) -> None:
    """
    Manually sync files from/to MinIO.
    """
    from copaw_worker.sync import FileSync

    sync_client = FileSync(
        endpoint=minio_endpoint,
        access_key=minio_access_key,
        secret_key=minio_secret_key,
        bucket=minio_bucket,
        worker_name=worker_name,
    )

    console.print(f"[cyan]Syncing files for worker {worker_name}...[/cyan]")

    try:
        if direction == "push":
            files = sync_client.push()
            console.print(f"[green]Pushed {len(files)} files to MinIO[/green]")
        else:
            files = sync_client.pull()
            console.print(f"[green]Pulled {len(files)} files from MinIO[/green]")

        for f in files[:10]:
            console.print(f"  - {f}")
        if len(files) > 10:
            console.print(f"  ... and {len(files) - 10} more")

    except Exception as e:
        console.print(f"[red]Sync failed: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def config() -> None:
    """
    Show current configuration (from environment variables).
    """
    try:
        cfg = WorkerConfig()
        console.print("[bold]Current Configuration:[/bold]")
        console.print(f"  worker_name: [cyan]{cfg.worker_name}[/cyan]")
        console.print(f"  matrix_server: {cfg.matrix_server}")
        console.print(f"  matrix_user: {cfg.matrix_user}")
        console.print(f"  ai_gateway: {cfg.ai_gateway}")
        console.print(f"  minio_endpoint: {cfg.minio_endpoint}")
        console.print(f"  minio_bucket: {cfg.minio_bucket}")
        console.print(f"  install_dir: {cfg.install_dir}")
        console.print(f"  model: {cfg.model}")
    except Exception as e:
        console.print(f"[red]Error loading config: {e}[/red]")
        console.print(
            "\n[yellow]Make sure all required environment variables are set:[/yellow]"
        )
        console.print("  HICLAW_WORKER_NAME")
        console.print("  HICLAW_MATRIX_SERVER")
        console.print("  HICLAW_MATRIX_PASSWORD")
        console.print("  HICLAW_AI_GATEWAY")
        console.print("  HICLAW_GATEWAY_TOKEN")
        console.print("  HICLAW_MINIO_ENDPOINT")
        console.print("  HICLAW_MINIO_ACCESS_KEY")
        console.print("  HICLAW_MINIO_SECRET_KEY")


if __name__ == "__main__":
    app()
