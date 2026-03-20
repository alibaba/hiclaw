"""Tests for bridge.py embedding config bridging."""

import json
import tempfile
from pathlib import Path

from copaw_worker.bridge import bridge_openclaw_to_copaw


def test_bridge_embedding_config():
    """memorySearch in openclaw.json should produce embedding_config in config.json."""
    openclaw_cfg = {
        "channels": {"matrix": {"enabled": True, "homeserver": "http://localhost:6167", "accessToken": "tok"}},
        "models": {
            "providers": {
                "gw": {"baseUrl": "http://aigw:8080/v1", "apiKey": "key123", "models": [{"id": "qwen3.5-plus", "name": "qwen3.5-plus"}]}
            }
        },
        "agents": {
            "defaults": {
                "model": {"primary": "gw/qwen3.5-plus"},
                "memorySearch": {
                    "provider": "openai",
                    "model": "text-embedding-v4",
                    "remote": {
                        "baseUrl": "http://aigw:8080/v1",
                        "apiKey": "key123",
                    },
                },
            }
        },
    }

    with tempfile.TemporaryDirectory() as tmpdir:
        working_dir = Path(tmpdir) / "agent"
        bridge_openclaw_to_copaw(openclaw_cfg, working_dir)

        config_path = working_dir / "config.json"
        assert config_path.exists()

        with open(config_path) as f:
            config = json.load(f)

        emb = config["agents"]["running"]["embedding_config"]
        assert emb["backend"] == "openai"
        assert emb["model_name"] == "text-embedding-v4"
        # _port_remap converts :8080 → :18080 when not in container
        assert "aigw" in emb["base_url"]
        assert emb["api_key"] == "key123"
        assert emb["dimensions"] == 1024
        assert emb["enable_cache"] is True


def test_bridge_no_embedding_config():
    """Without memorySearch, embedding_config should not be written."""
    openclaw_cfg = {
        "channels": {"matrix": {"enabled": True, "homeserver": "http://localhost:6167", "accessToken": "tok"}},
        "models": {
            "providers": {
                "gw": {"baseUrl": "http://aigw:8080/v1", "apiKey": "key123", "models": [{"id": "qwen3.5-plus", "name": "qwen3.5-plus"}]}
            }
        },
        "agents": {"defaults": {"model": {"primary": "gw/qwen3.5-plus"}}},
    }

    with tempfile.TemporaryDirectory() as tmpdir:
        working_dir = Path(tmpdir) / "agent"
        bridge_openclaw_to_copaw(openclaw_cfg, working_dir)

        with open(working_dir / "config.json") as f:
            config = json.load(f)

        running = config.get("agents", {}).get("running", {})
        assert "embedding_config" not in running
