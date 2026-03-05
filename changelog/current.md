# Changelog (Unreleased)

Record image-affecting changes to `manager/`, `worker/`, `openclaw-base/` here before the next release.

---

- feat(manager): add model-switch skill with `update-manager-model.sh` script for runtime model switching (00cbaa5)
- feat(manager): add task-management skill (extracted from AGENTS.md) covering task workflow and state file spec (00cbaa5)
- feat(manager): add `manager/scripts/lib/builtin-merge.sh` — shared library for idempotent builtin section merging (00cbaa5)
- fix(manager): fix `upgrade-builtins.sh` duplicate-insertion bug — awk now uses exact line match, preventing repeated marker injection on re-run (00cbaa5)
- fix(manager): detect and auto-repair corrupted AGENTS.md when marker count != 1 or heading is duplicated (47c5578, c28f82d, 078f3f8)
- feat(manager): expand worker-management skill and `lifecycle-worker.sh` with improved worker lifecycle handling (00cbaa5)
- fix(manager): `setup-higress.sh` — multiple route/consumer/MCP init fixes (d259177)
- fix(manager): `start-manager-agent.sh` — wait for Tuwunel Matrix API ready before proceeding, add detailed logging for token acquisition (d259177, 1a9e1d8)
- fix(manager): support Podman by replacing hardcoded `docker` commands with runtime detection; fix `jq` availability inside container; fix provider switch menu text (9d57ef8)
