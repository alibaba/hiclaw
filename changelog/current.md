# Changelog (Unreleased)

Record image-affecting changes to `manager/`, `worker/`, `openclaw-base/` here before the next release.

---

### Features

- **feat(manager): integrate mem0 plugin for long-term agent memory** — Add support for `@mem0/openclaw-mem0` plugin (Platform mode) with environment-driven configuration. The plugin enables automatic memory recall and capture across agent sessions via Mem0 Cloud. Configuration is injected at startup via `HICLAW_MEM0_*` environment variables (API key, user ID, org/project IDs, graph mode). Build-time bundling is optional via `MEM0_PLUGIN_ENABLED=1` build arg. Currently supports the Manager and OpenClaw Workers; CoPaw Workers are not supported yet.
- **fix(mem0): isolate worker memory per worker identity and install Mem0 via OpenClaw’s extension model on all OpenClaw images** — OpenClaw workers now always use their own `WORKER_NAME` as Mem0 `userId`, preventing cross-worker long-term memory collisions when `HICLAW_MEM0_USER_ID` is set at deployment scope. Mem0 bundling now follows the same extension-directory model as other OpenClaw plugins: the package tarball is unpacked into `/opt/openclaw/extensions/openclaw-mem0`, dependencies are installed inside that plugin directory, and runtime config adds both `plugins.allow` and `plugins.load.paths`. This avoids mutating OpenClaw’s `pnpm`-managed root project during image build or startup, and keeps `MEM0_PLUGIN_ENABLED=1` working across the Manager, aliyun Manager, and Worker images.
