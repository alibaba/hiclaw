# Changelog (Unreleased)

Record image-affecting changes to `manager/`, `worker/`, `openclaw-base/` here before the next release.

---

- feat(manager,worker): add local Codex runtime wiring so manager/workers can run as Codex sessions with host `~/.codex` auth and no API key ([71ef7a7](https://github.com/higress-group/hiclaw/commit/71ef7a7))
- fix(manager): preserve worker runtime when recreating local workers so codex workers do not fall back to openclaw (uncommitted)
- fix(manager,worker): send Matrix typing notifications while Codex runtime is handling a turn (uncommitted)
- fix(manager,worker): re-check Matrix room membership on each turn so DM rooms upgraded to groups do not stay misclassified (uncommitted)
- fix(worker): pass assigned Matrix room id into worker runtime and auto-join missing worker rooms on startup (uncommitted)
- fix(manager,worker): skip group-room router on explicit @mentions and keep the Codex app-server warm across turns to reduce reply latency (uncommitted)
- fix(manager): default the Manager to auto-follow allowed group-room conversations instead of requiring @mentions for every turn (uncommitted)
- feat(manager): make Manager proactively facilitate active project rooms with heartbeat-driven coordination updates and next-step assignment (uncommitted)
- fix(manager): bypass the lightweight Codex group-room router for Manager so project-room updates always reach the main coordination logic (uncommitted)
- fix(manager): update the live Manager allowlist config during project creation so Worker messages in project rooms trigger immediately across OpenClaw and CoPaw runtimes (uncommitted)
- fix(worker): stop syncing `.codex-home` runtime state through MinIO and ignore runtime-only changes in the 5-second worker sync loop (uncommitted)
- fix(worker): stop echoing manager-pulled `skills/` and `.mc.bin` runtime files back to MinIO after fallback/file-sync pulls (uncommitted)
- fix(worker): keep `.openclaw/cron/` synced so scheduled tasks still persist and Manager idle checks can see active cron jobs (uncommitted)
- fix(manager): treat task `result.md` as an authoritative completion signal during heartbeat/task-management flows instead of waiting only for a completion @mention (uncommitted)
- feat(manager): speed up manager-worker Matrix coordination with 120-second startup follow-up state and quiet-after-progress guidance (uncommitted)
