# Changelog (Unreleased)

Record image-affecting changes to `manager/`, `worker/`, `openclaw-base/` here before the next release.

---

### Features

- **feat(manager): integrate mem0 plugin for long-term agent memory** — Add support for `@mem0/openclaw-mem0` plugin (Platform mode) with environment-driven configuration. The plugin enables automatic memory recall and capture across agent sessions via Mem0 Cloud. Configuration is injected at startup via `HICLAW_MEM0_*` environment variables (API key, user ID, org/project IDs, graph mode). Build-time bundling is optional via `MEM0_PLUGIN_ENABLED=1` build arg. Currently supports the Manager and OpenClaw Workers; CoPaw Workers are not supported yet.
