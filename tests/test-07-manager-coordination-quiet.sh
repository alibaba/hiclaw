#!/bin/bash
# test-07-manager-coordination-quiet.sh - Case 7: Manager stays quiet after Worker startup signal
# Verifies: once Worker sends a clear startup/progress signal, heartbeat does not
#           send another start/blocker follow-up during the quiet window

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test-helpers.sh"
source "${SCRIPT_DIR}/lib/matrix-client.sh"
source "${SCRIPT_DIR}/lib/minio-client.sh"

find_room_with_members() {
    local token="$1"
    local required_count="$2"
    shift 2
    local required_users=("$@")

    local rooms
    rooms=$(matrix_joined_rooms "${token}" | jq -r '.joined_rooms[]') || return 1

    for room_id in ${rooms}; do
        local room_enc members member_count ok=1 user
        room_enc="${room_id//!/%21}"
        members=$(exec_in_manager curl -sf "${TEST_MATRIX_DIRECT_URL}/_matrix/client/v3/rooms/${room_enc}/members" \
            -H "Authorization: Bearer ${token}" 2>/dev/null | jq -r '.chunk[].state_key' 2>/dev/null) || continue
        member_count=$(echo "${members}" | grep -c '.' 2>/dev/null || echo 0)
        [ "${member_count}" -eq "${required_count}" ] || continue
        for user in "${required_users[@]}"; do
            if ! echo "${members}" | grep -q "${user}"; then
                ok=0
                break
            fi
        done
        [ "${ok}" -eq 1 ] || continue
        echo "${room_id}"
        return 0
    done

    return 1
}

test_setup "07-manager-coordination-quiet"

if ! require_llm_key; then
    test_teardown "07-manager-coordination-quiet"
    test_summary
    exit 0
fi

ADMIN_LOGIN=$(matrix_login "${TEST_ADMIN_USER}" "${TEST_ADMIN_PASSWORD}")
ADMIN_TOKEN=$(echo "${ADMIN_LOGIN}" | jq -r '.access_token')
MANAGER_USER="@manager:${TEST_MATRIX_DOMAIN}"
ALICE_USER="@alice:${TEST_MATRIX_DOMAIN}"

log_section "Assign Task And Get Worker Room"

DM_ROOM=$(matrix_find_dm_room "${ADMIN_TOKEN}" "${MANAGER_USER}" 2>/dev/null || true)
assert_not_empty "${DM_ROOM}" "Admin DM room with Manager found"

wait_for_manager_agent_ready 300 "${DM_ROOM}" "${ADMIN_TOKEN}" || {
    log_fail "Manager Agent not ready in time"
    test_teardown "07-manager-coordination-quiet"
    test_summary
    exit 1
}

minio_setup
minio_wait_for_file "agents/alice/openclaw.json" 120 || {
    log_fail "Alice openclaw.json available in MinIO"
    test_teardown "07-manager-coordination-quiet"
    test_summary
    exit 1
}
ALICE_TOKEN=$(minio_read_file "agents/alice/openclaw.json" | jq -r '.channels.matrix.accessToken // empty')
assert_not_empty "${ALICE_TOKEN}" "Alice Matrix access token available"

matrix_send_message "${ADMIN_TOKEN}" "${DM_ROOM}" \
    "Please assign Alice a task: Create a short API notes file and start immediately."

REPLY=$(matrix_wait_for_reply "${ADMIN_TOKEN}" "${DM_ROOM}" "@manager" 180 \
    "${ADMIN_TOKEN}" "${DM_ROOM}" "Please check if the task assignment has been processed.")
assert_not_empty "${REPLY}" "Manager acknowledged assignment"

ALICE_ROOM=""
for _ in $(seq 1 24); do
    ALICE_ROOM=$(find_room_with_members "${ADMIN_TOKEN}" 3 "${MANAGER_USER}" "${ALICE_USER}" 2>/dev/null || true)
    [ -n "${ALICE_ROOM}" ] && break
    sleep 5
done
assert_not_empty "${ALICE_ROOM}" "Alice three-party room found"

BASELINE_EVENT=$(matrix_read_messages "${ADMIN_TOKEN}" "${ALICE_ROOM}" 10 2>/dev/null | \
    jq -r '[.chunk[] | select(.sender | startswith("@manager")) | .event_id] | first // ""')
assert_not_empty "${BASELINE_EVENT}" "Baseline Manager event captured in Alice room"

log_section "Simulate Worker Startup Signal"
matrix_send_message "${ALICE_TOKEN}" "${ALICE_ROOM}" \
    "@manager:${TEST_MATRIX_DOMAIN} 收到，我先看 spec，开始处理。"

sleep 10

log_section "Trigger Heartbeat"
MANAGER_CONTAINER="${TEST_MANAGER_CONTAINER:-hiclaw-manager}"
MANAGER_RUNTIME=$(docker exec "${MANAGER_CONTAINER}" printenv HICLAW_MANAGER_RUNTIME 2>/dev/null || echo "openclaw")
log_info "Triggering heartbeat (runtime=${MANAGER_RUNTIME})..."

case "${MANAGER_RUNTIME}" in
    copaw)
        matrix_send_message "${ADMIN_TOKEN}" "${DM_ROOM}" \
            "Please execute your heartbeat check now. Read ~/HEARTBEAT.md and follow the full checklist. Report findings here."
        ;;
    *)
        docker exec "${MANAGER_CONTAINER}" bash -c \
            "cd ~/hiclaw-fs/agents/manager && openclaw system event --mode now" 2>/dev/null || \
            log_info "Could not trigger OpenClaw heartbeat via system event"
        ;;
esac

log_info "Waiting to confirm Manager stays quiet in Alice room..."
sleep 60

log_section "Verify No Extra Follow-up"
NEW_MANAGER_MESSAGES=$(matrix_read_messages "${ADMIN_TOKEN}" "${ALICE_ROOM}" 20 2>/dev/null | \
    jq -r --arg baseline "${BASELINE_EVENT}" '[.chunk[] | select((.sender | startswith("@manager")) and (.event_id != $baseline)) | .content.body // empty] | join("\n")')

if echo "${NEW_MANAGER_MESSAGES}" | grep -qiE 'started|start|blocked|task|开始|阻塞'; then
    log_fail "Manager sent an unnecessary start/blocker follow-up after Worker startup signal"
else
    log_pass "Manager stayed quiet after Worker startup signal"
fi

test_teardown "07-manager-coordination-quiet"
test_summary
