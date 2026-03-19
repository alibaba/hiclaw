---
name: file-sync
description: Sync files with centralized storage. Use when Manager or another Worker notifies you of file updates (config changes, task files, shared data, collaboration artifacts).
---

# File Sync (CoPaw Worker)

## Sync agent config files

When the Manager notifies you that your config has been updated (e.g., model switch, skill update), trigger an immediate sync:

```bash
copaw-sync
```

This pulls `openclaw.json`, `SOUL.md`, `AGENTS.md`, and skills from MinIO and re-bridges the config. CoPaw automatically hot-reloads config changes within ~2 seconds.

**Automatic background sync:**
- Background sync also runs every 300 seconds (5 minutes) as a fallback
- Config changes are automatically detected and hot-reloaded

## Sync task / shared files

The `shared/` directory is automatically mirrored from MinIO at startup and every sync cycle to `~/.copaw-worker/<your-name>/shared/`. No manual pull is needed.

Task and project files are at:

| Local path (auto-synced) |
|---|
| `~/.copaw-worker/<your-name>/shared/tasks/{task-id}/` |
| `~/.copaw-worker/<your-name>/shared/projects/{project-id}/` |

```bash
# Read the spec (already synced locally)
cat ~/.copaw-worker/<your-name>/shared/tasks/{task-id}/spec.md

# Push your results back to MinIO (push is still manual)
mc mirror ~/.copaw-worker/<your-name>/shared/tasks/{task-id}/ ${HICLAW_STORAGE_PREFIX}/shared/tasks/{task-id}/ \
  --overwrite --exclude "spec.md" --exclude "base/"
```

**When to use:**
- When you finish work: push results back to MinIO
- When told files have been updated urgently: run `copaw-sync` to trigger an immediate pull

Always confirm to the sender after push completes.

**Example workflow:**
```bash
# Manager assigns task: "New task [task-20260309-120000]. Pull spec from MinIO."
# shared/ is already synced — just read the spec
cat ~/.copaw-worker/<your-name>/shared/tasks/task-20260309-120000/spec.md

# ... do the work ...

# Push results
mc mirror ~/.copaw-worker/<your-name>/shared/tasks/task-20260309-120000/ \
  ${HICLAW_STORAGE_PREFIX}/shared/tasks/task-20260309-120000/ \
  --overwrite --exclude "spec.md" --exclude "base/"

# Confirm to Manager
"Task complete. Results pushed to MinIO."
```