# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is HiClaw

HiClaw is an open-source Collaborative Multi-Agent OS using Matrix protocol for human-in-the-loop task coordination. A Manager Agent coordinates Worker Agents, with all communication visible in Matrix rooms. Infrastructure: Higress AI Gateway, Tuwunel Matrix Server, MinIO file storage, Element Web client.

## Build & Test Commands

```bash
make build                              # Build all images (native arch)
make build-manager                      # Build Manager image only
make build-worker                       # Build Worker image only
make build-copaw-worker                 # Build CoPaw Worker image only
make build-orchestrator                 # Build Orchestrator image only (Go)
make build-openclaw-base                # Build base image (rarely needed)

make test                               # Build + install + run all integration tests
make test SKIP_INSTALL=1                # Run tests against existing Manager
make test TEST_FILTER="01 02"           # Run specific tests only
make test-quick                         # Smoke test (test-01 only)

make install                            # Build + install Manager locally
make uninstall                          # Stop + remove all containers

make status                             # Show all hiclaw container statuses
make logs                               # Show recent logs (LINES=N to override)
```

Orchestrator has its own Go test suite:
```bash
cd orchestrator && go test ./...        # Run Go unit tests
cd orchestrator && go test ./backend/...  # Run backend tests only
cd orchestrator && go test ./proxy/...    # Run security validation tests only
```

## Local Full Build (from modified openclaw-base)

Image dependency: `openclaw-base` → `manager` / `worker`. CoPaw and orchestrator are independent.

When building from a locally modified openclaw-base, you must override both variables:
```bash
make build-openclaw-base
make build-manager build-worker OPENCLAW_BASE_IMAGE=hiclaw/openclaw-base OPENCLAW_BASE_VERSION=latest
```

Without `OPENCLAW_BASE_IMAGE=hiclaw/openclaw-base`, it pulls from the remote registry instead of using your local build.

## Architecture

```
manager/              # All-in-one container: Higress + Tuwunel + MinIO + Element Web + OpenClaw Agent
  agent/              # Agent personality (SOUL.md), skills, tools — read by Agent at runtime
  scripts/init/       # Supervisord startup scripts for each service
  configs/            # Configuration templates (rendered at container start)
  supervisord.conf    # Process orchestration

worker/               # OpenClaw Worker container (Node.js 22)
copaw/                # CoPaw Worker container (Python 3.11, alternative runtime)
orchestrator/         # Go-based Worker lifecycle service (unified API + Docker proxy)
openclaw-base/        # Shared base image for manager + worker
shared/lib/           # Shared shell libraries (env bootstrap, credential mgmt, mc wrapper)
install/              # One-click installation scripts (bash + PowerShell)
tests/                # Integration test suite (14 cases)
  lib/                # Test helpers: assertions, Matrix client, Higress client, MinIO client
```

## Key Conventions

**Agent-facing content** (`manager/agent/**`): Written in second-person voice addressing the Agent directly ("You are...", "Your responsibilities..."). Never use third-person ("The Manager does X"). This applies to SOUL.md, AGENTS.md, HEARTBEAT.md, SKILL.md, TOOLS.md, and all worker-agent configs.

**Changelog policy**: Any change to `manager/`, `worker/`, `copaw/`, or `openclaw-base/` must be recorded in `changelog/current.md` before committing. Format: one bullet per logical change with linked commit hash.

**Shared build context**: Manager, Worker, and CoPaw Dockerfiles use `--build-context shared=./shared/lib` for shared shell libraries. The Makefile handles this automatically.

**Worker container naming**: All Worker containers must be prefixed `hiclaw-worker-` (enforced by orchestrator security validation).

## Integration Tests

Tests live in `tests/` and use bash-based helpers (`tests/lib/`). Each test is a standalone script (`tests/test-NN-*.sh`) that communicates with the Manager via Matrix API. Tests require a running Manager container with all services healthy.

Key test helpers:
- `tests/lib/test-helpers.sh` — assertions, lifecycle, logging
- `tests/lib/matrix-client.sh` — Matrix API wrapper (send messages, read rooms)
- `tests/lib/higress-client.sh` — Higress Console API wrapper
- `tests/lib/minio-client.sh` — MinIO verification

## Deployment Modes

- **Local**: All-in-one container with supervisord, Docker socket mounted for Worker management
- **Cloud (Alibaba SAE)**: Distributed containers, STS credential management, orchestrator for secure container API access

## Verified Technical Details

- Tuwunel uses `CONDUWUIT_` env prefix (not `TUWUNEL_`)
- Higress Console uses Session Cookie auth (not Basic Auth)
- MCP Server created via `PUT` (not `POST`)
- Auth plugin takes ~40s to activate after first configuration
- OpenClaw Skills auto-load from `workspace/skills/<name>/SKILL.md`
