# CoPaw Worker

Lightweight HiClaw Worker runtime based on [AgentScope](https://github.com/alibaba/AgentScope).

## Why CoPaw Worker?

Compared to the default HiClaw Worker (based on OpenClaw), CoPaw Worker offers:

- **Lower memory footprint** - ~100MB vs ~500MB per worker
- **Native Python** - Easy to extend and customize
- **Local model support** - Works with llama.cpp, MLX, Ollama
- **Simple deployment** - Just `pip install` and run

## Installation

```bash
pip install copaw-worker
```

## Quick Start

CoPaw Workers are created by the HiClaw Manager. After the Manager creates a worker, you'll receive an install command:

```bash
# Set environment variables
export HICLAW_WORKER_NAME=alice
export HICLAW_MATRIX_SERVER=https://matrix-local.hiclaw.io:8080
export HICLAW_MATRIX_USER=alice
export HICLAW_MATRIX_PASSWORD=<password>
export HICLAW_AI_GATEWAY=https://aigw-local.hiclaw.io
export HICLAW_GATEWAY_TOKEN=<token>
export HICLAW_MINIO_ENDPOINT=http://fs-local.hiclaw.io:8080
export HICLAW_MINIO_ACCESS_KEY=alice
export HICLAW_MINIO_SECRET_KEY=<secret>

# Run the worker
copaw-worker run
```

Or use command-line options:

```bash
copaw-worker run \
  --worker-name alice \
  --minio-endpoint http://fs-local.hiclaw.io:8080 \
  --minio-access-key alice \
  --minio-secret-key <secret>
```

## Configuration

Configuration can be provided via:

1. **Environment variables** (recommended for production)
2. **Command-line options** (overrides env vars)
3. **`.env` file** in the working directory

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `HICLAW_WORKER_NAME` | Unique worker name |
| `HICLAW_MATRIX_SERVER` | Matrix homeserver URL |
| `HICLAW_MATRIX_USER` | Matrix username |
| `HICLAW_MATRIX_PASSWORD` | Matrix password |
| `HICLAW_AI_GATEWAY` | AI Gateway URL |
| `HICLAW_GATEWAY_TOKEN` | Gateway authentication token |
| `HICLAW_MINIO_ENDPOINT` | MinIO endpoint URL |
| `HICLAW_MINIO_ACCESS_KEY` | MinIO access key |
| `HICLAW_MINIO_SECRET_KEY` | MinIO secret key |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HICLAW_MINIO_BUCKET` | `hiclaw-storage` | MinIO bucket name |
| `HICLAW_INSTALL_DIR` | `~/.copaw-worker` | Installation directory |
| `HICLAW_MODEL` | `qwen3.5-plus` | LLM model to use |
| `HICLAW_SKILLS_API_URL` | - | Skills API URL |
| `HICLAW_LOG_LEVEL` | `INFO` | Logging level |

## Commands

```bash
# Start the worker
copaw-worker run

# Manually sync files from MinIO
copaw-worker sync

# Show current configuration
copaw-worker config

# Show version
copaw-worker --version
```

## Development

```bash
# Clone the HiClaw repository
git clone https://github.com/higress-group/hiclaw.git
cd hiclaw/copaw

# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install in development mode
pip install -e ".[dev]"

# Run tests
pytest

# Run linter
ruff check src/

# Format code
ruff format src/
```

## Architecture

```
CoPaw Worker
├── CLI (cli.py)         - Command-line interface
├── Config (config.py)   - Configuration management
├── Agent (agent.py)     - Main agent loop
├── Matrix (matrix.py)   - Matrix client
├── Sync (sync.py)       - MinIO file sync
└── Skills (skills.py)   - Skill loading/execution
```

## License

Apache License 2.0
