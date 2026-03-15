## Manager Heartbeat Checklist

### 1. Read state.json

Read state.json (local only, no sync needed). If the file does not exist, initialize it first:

```bash
bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh --action init
cat ~/state.json
```

The `active_tasks` field in state.json contains all in-progress tasks (both finite and infinite). No need to iterate over all meta.json files.

**Ensure admin notification channel is available** (used in Step 7):

1. Check `admin_dm_room_id` in state.json. If `null`, discover it now:
   - List joined rooms, find the DM room with exactly 2 members: you and `@${HICLAW_ADMIN_USER}:${HICLAW_MATRIX_DOMAIN}`
   - Persist it:
     ```bash
     bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh \
       --action set-admin-dm --room-id "<discovered-room-id>"
     ```
2. Verify the channel is resolvable:
   ```bash
   bash /opt/hiclaw/agent/skills/task-management/scripts/resolve-notify-channel.sh
   ```
   If the output shows `"channel": "none"`, the admin DM room discovery above may have failed — retry or log a warning.

---

### 2. Check Status of Finite Tasks

Iterate over entries in `active_tasks` with `"type": "finite"`:

- Read `assigned_to`, `room_id`, and `project_room_id` (if present) from the entry
- Determine the target room: use `project_room_id` if available, otherwise use `room_id`
- **Use the `message` tool** to send a follow-up to that room, with `user_id` set to the Worker's Matrix ID (`@{worker}:${HICLAW_MATRIX_DOMAIN}`):
  ```
  room_id: <room_id from state.json>
  user_id: @{worker}:${HICLAW_MATRIX_DOMAIN}
  message: @{worker}:{domain} How is your current task {task-id} going? Are you blocked on anything?
  ```
- Determine if the Worker is making normal progress based on their reply
- If the Worker has not responded (no response for more than one heartbeat cycle), flag the anomaly in the Room and notify the human admin (see Step 7)
- If the Worker has replied that the task is complete but meta.json has not been updated, proactively update meta.json (status → completed, fill in completed_at), and remove the entry from `active_tasks`:
  ```bash
  bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh --action complete --task-id {task-id}
  ```

---

### 3. Check Infinite Task Timeouts

Iterate over entries in `active_tasks` with `"type": "infinite"`. For each entry:

```
Current UTC time = now

Conditions (both must be met):
  1. last_executed_at < next_scheduled_at (not yet executed this cycle)
     OR last_executed_at is null (never executed)
  2. now > next_scheduled_at + 30 minutes (overdue)
```

If conditions are met, read `room_id` from the entry and **use the `message` tool** to trigger execution:
```
room_id: <room_id from state.json>
user_id: @{worker}:${HICLAW_MATRIX_DOMAIN}
message: @{worker}:{domain} It's time to run your scheduled task {task-id} "{task-title}". Please execute it now and report back with the keyword "executed".
```

**Note**: Infinite tasks are never removed from active_tasks. After the Worker reports `executed`, update `last_executed_at` and `next_scheduled_at`:
```bash
bash /opt/hiclaw/agent/skills/task-management/scripts/manage-state.sh \
  --action executed --task-id {task-id} --next-scheduled-at "{new-ISO-8601}"
```

---

### 4. Project Progress Monitoring

Scan plan.md for all active projects under /root/hiclaw-fs/shared/projects/:

```bash
for meta in /root/hiclaw-fs/shared/projects/*/meta.json; do
  cat "$meta"
done
```

- Filter projects with `"status": "active"`
- For each active project, read `project_room_id` from meta.json, then read plan.md and find tasks marked as `[~]` (in progress)
- If the responsible Worker has had no activity during this heartbeat cycle, **use the `message` tool** to send a follow-up to the project room:
  ```
  room_id: <project_room_id from meta.json>
  user_id: @{worker}:${HICLAW_MATRIX_DOMAIN}
  message: @{worker}:{domain} Any progress on your current task {task-id} "{title}"? Please let us know if you're blocked.
  ```
- If a Worker has reported task completion in the project room but plan.md has not been updated yet, handle it immediately (see the project management section in AGENTS.md)

---

### 5. Capacity Assessment

- Count the number of `type=finite` entries in state.json (finite tasks in progress) and identify idle Workers with no assigned tasks (neither finite nor infinite)
- If Workers are insufficient, check in with the human admin about whether new Workers need to be created
- If Workers are idle, suggest reassigning tasks

---

### 6. Worker Container Lifecycle Management

Only execute when the container API is available (check first):

```bash
bash -c 'source /opt/hiclaw/scripts/lib/container-api.sh && container_api_available && echo available'
```

If the output is `available`, proceed with the following steps:

1. Sync status:
   ```bash
   bash /opt/hiclaw/agent/skills/worker-management/scripts/lifecycle-worker.sh --action sync-status
   ```

2. Detect idle Workers: For each Worker, if there are no active tasks (neither finite nor infinite) for them in state.json and container_status=running:
   - If idle_since is not set, set it to the current time
   - If (now - idle_since) > idle_timeout_minutes, perform auto-stop:
     ```bash
     bash /opt/hiclaw/agent/skills/worker-management/scripts/lifecycle-worker.sh --action check-idle
     ```
   - Look up the Worker's `room_id` from `workers-registry.json` and **use the `message` tool** to log:
     ```
     room_id: <Worker's room_id from workers-registry.json>
     message: Worker <name> container has been automatically paused due to idle timeout. It will be automatically resumed when a task is assigned.
     ```

3. If a Worker has an active task (finite or infinite) but its container status is `stopped` or `not_found` (anomaly), start/recreate it and send an alert to the admin (see Step 7):
   ```bash
   bash /opt/hiclaw/agent/skills/worker-management/scripts/lifecycle-worker.sh --action start --worker <name>
   ```
   The `start` action automatically handles both cases: if the container exists but is stopped it will be started; if the container is missing it will be recreated from credentials and registry config.

---

### 7. Report to Admin

**All heartbeat findings MUST be sent to the admin via the `message` tool** (not as a reply in the current heartbeat context).

- If all Workers are healthy and there are no pending items: HEARTBEAT_OK (no message needed)
- Otherwise, **read SOUL.md first** — use the identity, personality, and **user's preferred language** defined there when composing the report. Report in that language and tone.
- Resolve the notification channel:
  ```bash
  bash /opt/hiclaw/agent/skills/task-management/scripts/resolve-notify-channel.sh
  ```
  The script outputs JSON with `channel`, `target`, and `via` fields. Use the `message` tool with those values:
  - If `channel` is not `"none"`: send `[Heartbeat Report] <summarize findings and recommended actions, in SOUL.md persona and language>` to the resolved `target`.
  - If `channel` is `"none"`: admin DM room has not been discovered yet — attempt discovery now (see Step 1), then retry.
