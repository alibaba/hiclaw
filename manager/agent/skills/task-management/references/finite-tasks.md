# Finite Task Workflow

## Choosing task type

- **Finite** — clear end state. Worker delivers result, it's done. Examples: "implement login page", "fix bug #123", "write a report".
- **Infinite** — repeats on schedule, no natural end. See `references/infinite-tasks.md`.

**Rule**: if the request contains a recurring schedule or implies ongoing monitoring, use infinite. Everything else is finite.

## Assigning a finite task

1. Generate task ID: `task-YYYYMMDD-HHMMSS`
2. Create task directory and files:
   ```bash
   mkdir -p /root/hiclaw-fs/shared/tasks/{task-id}
   ```
   Write `meta.json` (type: "finite", status: "assigned") and `spec.md` (requirements, acceptance criteria, context).

3. Push to MinIO **immediately** — Worker cannot file-sync until files are in MinIO:
   ```bash
   mc cp /root/hiclaw-fs/shared/tasks/{task-id}/meta.json ${HICLAW_STORAGE_PREFIX}/shared/tasks/{task-id}/meta.json
   mc cp /root/hiclaw-fs/shared/tasks/{task-id}/spec.md ${HICLAW_STORAGE_PREFIX}/shared/tasks/{task-id}/spec.md
   ```
   **Verify the push succeeded** (non-zero exit = retry). Do NOT proceed to step 4 until files are confirmed in MinIO.

4. Notify Worker in their Room:
   ```
   @{worker}:{domain} New task [{task-id}]: {title}. Use your file-sync skill to pull the spec: shared/tasks/{task-id}/spec.md. @mention me when complete.
   ```

5. **MANDATORY — Add to state.json** (this step is NOT optional, even for coordination, research, or management tasks):
   ```bash
   bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh \
     --action add-finite --task-id {task-id} --title "{title}" \
     --assigned-to {worker} --room-id {room-id}
   ```
   If task belongs to a project, append `--project-room-id {project-room-id}`.
   **WARNING**: Skipping this step causes the Worker to be auto-stopped by idle timeout. Every task assigned to a Worker MUST be registered here.

## Coordination metadata

When you call `add-finite`, the script also initializes lightweight coordination metadata in `state.json`:

- `delegated_at`
- `worker_signal_state = "pending"`
- `worker_last_signal_at = null`
- `manager_last_followup_at = null`
- `manager_escalated_at = null`
- `manager_quiet_until`

Use these fields to decide whether you should follow up, escalate, or stay quiet. The 120-second coordination timeout is for missing startup/progress signals only — not for deciding that the Worker has failed the task.

## Recording Worker signals

If the Worker clearly acknowledges, starts, reports progress, or reports a blocker, record it immediately:

```bash
bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh \
  --action record-signal --task-id {task-id} --worker-signal-state acknowledged
```

Supported `worker_signal_state` values:

- `pending`
- `acknowledged`
- `in_progress`
- `blocked`
- `completed`

Use them like this:

- `acknowledged` — the Worker has accepted the task
- `in_progress` — the Worker has started or reported progress
- `blocked` — the Worker reported a real blocker
- `completed` — the Worker explicitly reported completion before you run the normal completion flow

After a real Worker signal, stay quiet until a new blocker or a later timeout appears.

## Following up and escalating

If the Worker has not sent any startup/progress signal within the 120-second coordination timeout, follow up once and record it:

```bash
bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh \
  --action mark-followup --task-id {task-id}
```

If silence continues after that, escalate to the admin and record it:

```bash
bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh \
  --action mark-escalated --task-id {task-id}
```

Do not reassign the task because of this coordination timeout. Different Workers have different responsibilities, so you should escalate instead of switching owners.

## On completion

Completion can be triggered in two ways:
- the Worker @mentions you with a completion report
- you discover that `shared/tasks/{task-id}/result.md` already exists and is non-empty during heartbeat or room follow-up

`result.md` is authoritative enough to start completion handling. Do not wait for an extra @mention once the result is already there.

1. Pull task directory from MinIO (Worker has pushed results):
   ```bash
   mc mirror ${HICLAW_STORAGE_PREFIX}/shared/tasks/{task-id}/ /root/hiclaw-fs/shared/tasks/{task-id}/ --overwrite
   ```
2. Update `meta.json`: status=completed, fill completed_at. Push back to MinIO.
3. Remove from state.json:
   ```bash
   bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh \
     --action complete --task-id {task-id}
   ```
4. Log to `memory/YYYY-MM-DD.md`.
5. Notify admin — read SOUL.md first for persona/language, then resolve channel:
   ```bash
   bash /opt/hiclaw/agent/skills/task-management/scripts/resolve-notify-channel.sh
   ```
   - If `channel` is not `"none"`: send `[Task Completed] {task-id}: {title} — assigned to {worker}. {summary}` to resolved target.
   - If `channel` is `"none"`: the admin DM room is not yet cached. Discover it now — list joined rooms, find the DM room with exactly 2 members (you and admin), then persist:
     ```bash
     bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh \
       --action set-admin-dm --room-id "<discovered-room-id>"
     ```
     After persisting, retry `resolve-notify-channel.sh` and send the notification. If discovery fails, log a warning and move on — heartbeat will catch up.

## Task directory layout

```
shared/tasks/{task-id}/
├── meta.json     # Manager-maintained
├── spec.md       # Manager-written
├── base/         # Manager-maintained reference files (Workers must not overwrite)
├── plan.md       # Worker-written execution plan
├── result.md     # Worker-written final result
└── *             # Intermediate artifacts
```
