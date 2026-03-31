---
name: team-task-management
description: Use when you need to assign tasks to team workers, track team task progress, find available workers in your team, or manage team-state.json.
---

# Team Task Management

Manage individual tasks within your team. For complex multi-worker tasks with dependencies, use `team-project-management` instead.

## Task Sources

| Source | Channel | Result destination | Report to |
|--------|---------|-------------------|-----------|
| Manager | Leader Room @mention | `shared/tasks/{parent-task-id}/result.md` | Manager in Leader Room |
| Team Admin | Leader DM message | `teams/{team}/tasks/{task-id}/result.md` | Team Admin in Leader DM |

## Key Scripts

```bash
# Find available team workers
bash ~/skills/team-task-management/scripts/find-team-worker.sh

# Add a task (use --source manager/team-admin, --parent-task-id, --requester as needed)
bash ~/skills/team-task-management/scripts/manage-team-state.sh \
  --action add-finite --task-id st-01 --title "Implement auth" \
  --assigned-to alice --room-id '!room:domain' \
  --source manager --parent-task-id task-xxx

# Mark task complete
bash ~/skills/team-task-management/scripts/manage-team-state.sh \
  --action complete --task-id st-01

# List all active team tasks and projects
bash ~/skills/team-task-management/scripts/manage-team-state.sh --action list
```

## Gotchas

- **Always push to MinIO before notifying workers** — workers need to file-sync to get specs
- **Always pull from MinIO before reading results** — workers push results there
- **Always use manage-team-state.sh** for state changes — never edit JSON manually
- **Route completion by source** — check `source` field to decide where to report

## References

Read the relevant doc **before** executing. Do not load all of them.

| Situation | Read |
|---|---|
| Assign a task or handle completion | `references/finite-tasks.md` |
| Need to pick a worker | `references/worker-selection.md` |
| State management details | `references/state-management.md` |
