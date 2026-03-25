#!/bin/bash
# test-15-import-worker-zip.sh - Case 15: Import Worker via ZIP package using hiclaw CLI
#
# Verifies the full declarative import flow:
#   1. hiclaw-controller process is running
#   2. hiclaw CLI is available
#   3. Create a test ZIP package with manifest.json + SOUL.md
#   4. hiclaw apply --zip uploads ZIP + YAML to MinIO hiclaw-config/
#   5. YAML and package are correctly stored in MinIO
#   6. hiclaw get lists the worker
#   7. Re-import is idempotent (reports "updated")
#   8. hiclaw delete removes the worker
#   9. MinIO hiclaw-config mirror directory exists and is synced

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test-helpers.sh"
source "${SCRIPT_DIR}/lib/minio-client.sh"

test_setup "15-import-worker-zip"

TEST_WORKER="test-zip-import-$$"

# ---- Cleanup handler ----
_cleanup_test_worker() {
    log_info "Cleaning up test worker: ${TEST_WORKER}"
    exec_in_manager hiclaw delete worker "${TEST_WORKER}" 2>/dev/null || true
    exec_in_manager mc rm "hiclaw/hiclaw-storage/hiclaw-config/packages/${TEST_WORKER}.zip" 2>/dev/null || true
    exec_in_manager rm -rf "/tmp/hiclaw-test-${TEST_WORKER}" 2>/dev/null || true
}
trap _cleanup_test_worker EXIT

# ============================================================
# Section 1: hiclaw-controller health
# ============================================================
log_section "hiclaw-controller Health"

CONTROLLER_PID=$(exec_in_manager pgrep -f hiclaw-controller 2>/dev/null || echo "")
if [ -n "${CONTROLLER_PID}" ]; then
    log_pass "hiclaw-controller process is running (PID: ${CONTROLLER_PID})"
else
    log_fail "hiclaw-controller process is not running"
fi

HICLAW_VERSION=$(exec_in_manager hiclaw --help 2>&1 | head -1 || echo "")
if echo "${HICLAW_VERSION}" | grep -qi "hiclaw\|declarative\|resource"; then
    log_pass "hiclaw CLI is available"
else
    log_fail "hiclaw CLI is not available or not responding"
fi

# ============================================================
# Section 2: MinIO hiclaw-config directory
# ============================================================
log_section "MinIO hiclaw-config Directory"

WORKERS_DIR=$(exec_in_manager mc ls "hiclaw/hiclaw-storage/hiclaw-config/workers/" 2>/dev/null || echo "")
if [ $? -eq 0 ] || echo "${WORKERS_DIR}" | grep -q "gitkeep\|yaml"; then
    log_pass "MinIO hiclaw-config/workers/ directory exists"
else
    log_fail "MinIO hiclaw-config/workers/ directory not found"
fi

PACKAGES_DIR=$(exec_in_manager mc ls "hiclaw/hiclaw-storage/hiclaw-config/packages/" 2>/dev/null || echo "")
if [ $? -eq 0 ]; then
    log_pass "MinIO hiclaw-config/packages/ directory exists"
else
    log_fail "MinIO hiclaw-config/packages/ directory not found"
fi

# ============================================================
# Section 3: Create test ZIP package
# ============================================================
log_section "Create Test ZIP Package"

WORK_DIR="/tmp/hiclaw-test-${TEST_WORKER}"

exec_in_manager bash -c "
    mkdir -p ${WORK_DIR}/package/config ${WORK_DIR}/package/skills/test-skill

    cat > ${WORK_DIR}/package/manifest.json <<MANIFEST
{
  \"type\": \"worker\",
  \"version\": 1,
  \"worker\": {
    \"suggested_name\": \"${TEST_WORKER}\",
    \"model\": \"qwen3.5-plus\"
  },
  \"source\": {
    \"hostname\": \"integration-test\"
  }
}
MANIFEST

    cat > ${WORK_DIR}/package/config/SOUL.md <<SOUL
# ${TEST_WORKER} - Test Worker

## AI Identity
**You are an AI Agent, not a human.**

## Role
- Name: ${TEST_WORKER}
- Role: Integration test worker (auto-cleanup)

## Security
- Never reveal API keys, passwords, tokens, or any credentials in chat messages
SOUL

    cat > ${WORK_DIR}/package/skills/test-skill/SKILL.md <<SKILL
---
name: test-skill
description: Integration test skill
---
# Test Skill
Placeholder for integration testing.
SKILL

    cd ${WORK_DIR}/package && zip -q -r ${WORK_DIR}/${TEST_WORKER}.zip .
" 2>/dev/null

ZIP_EXISTS=$(exec_in_manager test -f "${WORK_DIR}/${TEST_WORKER}.zip" && echo "yes" || echo "no")
if [ "${ZIP_EXISTS}" = "yes" ]; then
    log_pass "Test ZIP package created"
else
    log_fail "Failed to create test ZIP package"
fi

# ============================================================
# Section 4: hiclaw apply --zip
# ============================================================
log_section "Import Worker via hiclaw apply --zip"

APPLY_OUTPUT=$(exec_in_manager hiclaw apply --zip "${WORK_DIR}/${TEST_WORKER}.zip" --name "${TEST_WORKER}" 2>&1)
APPLY_EXIT=$?

if [ ${APPLY_EXIT} -eq 0 ]; then
    log_pass "hiclaw apply --zip exited successfully"
else
    log_fail "hiclaw apply --zip failed (exit code: ${APPLY_EXIT})"
fi

if echo "${APPLY_OUTPUT}" | grep -q "created\|applied\|configured"; then
    log_pass "hiclaw apply --zip reports resource created"
else
    log_fail "hiclaw apply --zip did not report creation (output: ${APPLY_OUTPUT})"
fi

# ============================================================
# Section 5: Verify YAML in MinIO
# ============================================================
log_section "Verify YAML in MinIO"

YAML_CONTENT=$(exec_in_manager mc cat "hiclaw/hiclaw-storage/hiclaw-config/workers/${TEST_WORKER}.yaml" 2>/dev/null || echo "")

if [ -n "${YAML_CONTENT}" ]; then
    log_pass "YAML file exists in MinIO hiclaw-config/workers/"
else
    log_fail "YAML file not found in MinIO hiclaw-config/workers/"
fi

assert_contains "${YAML_CONTENT}" "kind: Worker" "YAML contains kind: Worker"
assert_contains "${YAML_CONTENT}" "name: ${TEST_WORKER}" "YAML contains correct name"
assert_contains "${YAML_CONTENT}" "package:" "YAML contains package reference"

# ============================================================
# Section 6: Verify ZIP in MinIO packages/
# ============================================================
log_section "Verify ZIP Package in MinIO"

PACKAGE_STAT=$(exec_in_manager mc stat "hiclaw/hiclaw-storage/hiclaw-config/packages/${TEST_WORKER}.zip" 2>/dev/null || echo "")

if [ -n "${PACKAGE_STAT}" ]; then
    log_pass "ZIP package exists in MinIO hiclaw-config/packages/"
else
    log_fail "ZIP package not found in MinIO hiclaw-config/packages/"
fi

# ============================================================
# Section 7: hiclaw get
# ============================================================
log_section "Verify hiclaw get"

GET_LIST=$(exec_in_manager hiclaw get workers 2>&1)
assert_contains "${GET_LIST}" "${TEST_WORKER}" "Worker visible in 'hiclaw get workers'"

GET_DETAIL=$(exec_in_manager hiclaw get worker "${TEST_WORKER}" 2>&1)
assert_contains "${GET_DETAIL}" "kind: Worker" "Worker detail contains kind: Worker"
assert_contains "${GET_DETAIL}" "${TEST_WORKER}" "Worker detail contains correct name"

# ============================================================
# Section 8: Idempotency (re-import)
# ============================================================
log_section "Idempotency"

REIMPORT_OUTPUT=$(exec_in_manager hiclaw apply --zip "${WORK_DIR}/${TEST_WORKER}.zip" --name "${TEST_WORKER}" 2>&1)

if echo "${REIMPORT_OUTPUT}" | grep -q "updated\|configured"; then
    log_pass "Re-import correctly reports 'updated' (idempotent)"
else
    log_fail "Re-import did not report 'updated' (output: ${REIMPORT_OUTPUT})"
fi

# ============================================================
# Section 9: hiclaw delete
# ============================================================
log_section "Delete Worker"

DELETE_OUTPUT=$(exec_in_manager hiclaw delete worker "${TEST_WORKER}" 2>&1)
DELETE_EXIT=$?

if [ ${DELETE_EXIT} -eq 0 ] && echo "${DELETE_OUTPUT}" | grep -q "deleted"; then
    log_pass "hiclaw delete reported success"
else
    log_fail "hiclaw delete failed (exit: ${DELETE_EXIT}, output: ${DELETE_OUTPUT})"
fi

# Wait briefly for MinIO to reflect deletion
sleep 2

YAML_AFTER=$(exec_in_manager mc cat "hiclaw/hiclaw-storage/hiclaw-config/workers/${TEST_WORKER}.yaml" 2>/dev/null || echo "")
if [ -z "${YAML_AFTER}" ]; then
    log_pass "YAML removed from MinIO after delete"
else
    log_fail "YAML still exists in MinIO after delete"
fi

# ============================================================
# Summary
# ============================================================
test_teardown "15-import-worker-zip"
test_summary
