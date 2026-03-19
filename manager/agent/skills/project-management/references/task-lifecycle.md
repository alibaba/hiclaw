# Task Lifecycle (Assign → Complete → Next)

## Assign a Task (Step 2)

### 2a. Create task files

```bash
TASK_ID="task-$(date +%Y%m%d-%H%M%S)"
mkdir -p /root/hiclaw-fs/shared/tasks/${TASK_ID}
```

Write `meta.json`:
```json
{
  "task_id": "<task-id>",
  "project_id": "<project-id>",
  "task_title": "<title>",
  "assigned_to": "<worker-name>",
  "room_id": "<project-room-id>",
  "status": "assigned",
  "depends_on": [],
  "assigned_at": "<ISO-8601>"
}
```

Write `spec.md` with: task title, project context, deliverables, constraints, and the Task Directory Convention:
- Worker creates `plan.md` before starting
- All artifacts stay in the task directory
- Worker writes `result.md` when done
- Worker pushes with: `mc mirror ... --overwrite --exclude "spec.md" --exclude "base/"` (spec.md and base/ are Manager-owned)

### 2b. Sync to MinIO

```bash
mc cp /root/hiclaw-fs/shared/tasks/${TASK_ID}/meta.json ${HICLAW_STORAGE_PREFIX}/shared/tasks/${TASK_ID}/meta.json
mc cp /root/hiclaw-fs/shared/tasks/${TASK_ID}/spec.md ${HICLAW_STORAGE_PREFIX}/shared/tasks/${TASK_ID}/spec.md
```

### 2c. Update plan.md

Change `[ ]` to `[~]` for the task. Sync plan.md to MinIO.

### 2d. @mention Worker in Project Room

Adapt language to admin's preferred language:
```
@{worker}:{domain} New task [{task-id}]: {task title}

{2-3 sentence summary}

Full spec: ${HICLAW_STORAGE_PREFIX}/shared/tasks/{task-id}/spec.md

Please file-sync, read the spec, create plan.md before starting. @mention me when complete.
```

---

## Handle Completion (Step 3)

### 3a. Parse task outcome

Pull task directory from MinIO, then read `result.md` for the Outcome status: `SUCCESS`, `SUCCESS_WITH_NOTES`, `REVISION_NEEDED`, or `BLOCKED`.

### 3b. REVISION_NEEDED → Trigger revision

1. Find revision target in plan.md (`On REVISION_NEEDED:` directive)
2. Identify who revises (`return to {task-id}` → original assignee, `reassign to @{worker}` → specified worker)
3. Create revision task: `meta.json` with `is_revision_for` and `triggered_by` fields, `spec.md` referencing the feedback source
4. Push to MinIO, add revision task to plan.md
5. @mention the worker in project room
6. **Do NOT proceed to next phase** until revision is complete

### 3c. BLOCKED → Handle blocker

See `references/plan-changes.md` Step 4.

### 3d. SUCCESS / SUCCESS_WITH_NOTES

1. Update `meta.json`: `status → completed`, fill `completed_at`
2. Sync to MinIO
3. Update plan.md: `[~]` → `[x]`, add Change Log entry
4. If `SUCCESS_WITH_NOTES`, record notes for reference
5. Notify admin about completion:
   ```bash
   bash /opt/hiclaw/agent/skills/task-management/scripts/resolve-notify-channel.sh
   ```
   Send `[Project Task Completed] {project-title} — {task-id}: {task title} by {worker}. {summary}` to resolved channel. Read SOUL.md first for persona and language.
6. Proceed to find next tasks (3e)

### 3e. Find next tasks

Read plan.md, find `[ ]` tasks whose dependencies are all `[x]`. For each newly unblocked task, go to Step 2.

If the same Worker has another task ready, assign immediately — they're available and context-fresh.

### 3f. All tasks complete

**Mandatory — always execute, including in YOLO mode.**

1. Update meta.json: `status → completed`
2. Update plan.md Status to "completed"
3. Sync to MinIO
4. Post completion summary in project room, @mention admin
5. Update `memory/YYYY-MM-DD.md` with project outcome
