#!/bin/bash
# test-14-git-collab.sh - Case 14: Non-linear multi-Worker local git collaboration
# Verifies: 4-phase PR-style collaboration using local bare git repo (no GitHub required):
#   Phase 1 (alice): implement feature on a branch
#   Phase 2 (bob): review and request changes via a review branch
#   Phase 3 (alice): fix based on review, update branch
#   Phase 4 (charlie): add tests on a test branch

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test-helpers.sh"
source "${SCRIPT_DIR}/lib/matrix-client.sh"
source "${SCRIPT_DIR}/lib/agent-metrics.sh"

test_setup "14-git-collab"

if ! require_llm_key; then
    test_teardown "14-git-collab"
    test_summary
    exit 0
fi

ADMIN_LOGIN=$(matrix_login "${TEST_ADMIN_USER}" "${TEST_ADMIN_PASSWORD}")
ADMIN_TOKEN=$(echo "${ADMIN_LOGIN}" | jq -r '.access_token')

MANAGER_USER="@manager:${TEST_MATRIX_DOMAIN}"

# Generate unique branch names for this test run
TEST_RUN_ID=$(date +%s)
REPO_PATH="/root/git-repos/collab-test-${TEST_RUN_ID}"
FEATURE_BRANCH="feature/math-utils-${TEST_RUN_ID}"
REVIEW_BRANCH="review/math-utils-${TEST_RUN_ID}"
TEST_BRANCH="test/math-utils-${TEST_RUN_ID}"

log_section "Setup: Initialize Bare Git Repo"

docker exec "${TEST_MANAGER_CONTAINER}" bash -c "
    set -e
    mkdir -p '${REPO_PATH}.git'
    git init --bare '${REPO_PATH}.git'
    tmpdir=\$(mktemp -d)
    git -C \"\$tmpdir\" init
    git -C \"\$tmpdir\" remote add origin '${REPO_PATH}.git'
    echo '# Collab Test Project' > \"\$tmpdir/README.md\"
    git -C \"\$tmpdir\" add .
    git -C \"\$tmpdir\" -c user.email='setup@hiclaw.io' -c user.name='Setup' -c core.hooksPath=/dev/null commit -m 'Initial commit'
    git -C \"\$tmpdir\" push origin HEAD:main
    rm -rf \"\$tmpdir\"
" || {
    log_fail "Failed to initialize bare git repo"
    test_teardown "14-git-collab"
    test_summary
    exit 1
}
log_pass "Bare git repo initialized at ${REPO_PATH}.git"

# Start git daemon so worker containers can access the repo via git:// protocol
MANAGER_IP=$(docker inspect "${TEST_MANAGER_CONTAINER}" \
    --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
docker exec "${TEST_MANAGER_CONTAINER}" bash -c "
    git daemon --base-path=/root/git-repos \
        --export-all --enable=receive-pack \
        --reuseaddr --port=9418 \
        --pid-file=/tmp/git-daemon.pid \
        --detach 2>/dev/null || true
"
sleep 2
GIT_REPO_URL="git://${MANAGER_IP}/collab-test-${TEST_RUN_ID}"
log_info "Git daemon started; repo URL for workers: ${GIT_REPO_URL}"

log_section "Setup: Find or Create DM Room"

DM_ROOM=$(matrix_find_dm_room "${ADMIN_TOKEN}" "${MANAGER_USER}" 2>/dev/null || true)

if [ -z "${DM_ROOM}" ]; then
    log_info "Creating DM room with Manager..."
    DM_ROOM=$(matrix_create_dm_room "${ADMIN_TOKEN}" "${MANAGER_USER}")
    sleep 5
fi

assert_not_empty "${DM_ROOM}" "DM room with Manager exists"

wait_for_manager_agent_ready 300 "${DM_ROOM}" "${ADMIN_TOKEN}" || {
    log_fail "Manager Agent not ready in time"
    docker exec "${TEST_MANAGER_CONTAINER}" rm -rf "${REPO_PATH}.git" 2>/dev/null || true
    test_teardown "14-git-collab"
    test_summary
    exit 1
}

log_section "Phase 1-4: Assign 4-Phase Git Collaboration Task"

TASK_DESCRIPTION="Please coordinate a 4-phase local git collaboration workflow.

Git repo URL (accessible from all worker containers): ${GIT_REPO_URL}
The repo is already initialized with a 'main' branch.

Ensure workers alice (developer), bob (reviewer), and charlie (qa-tester) exist with the git-delegation skill. Then run the following phases in order:

**Phase 1 - Feature Development (alice)**:
- Clone ${GIT_REPO_URL}, create branch '${FEATURE_BRANCH}' from main
- Add file 'src/math_utils.py' with: add(a, b) returning a+b, multiply(a, b) returning a*b
- Commit 'feat: add math utils' and push to ${GIT_REPO_URL}
- Report PHASE1_DONE

**Phase 2 - Code Review (bob)** — after alice reports PHASE1_DONE:
- Clone ${GIT_REPO_URL}, check out '${FEATURE_BRANCH}', review src/math_utils.py
- Create branch '${REVIEW_BRANCH}', add 'reviews/math-utils-review.md' with feedback: 'Please add input type validation — raise TypeError if inputs are not int or float'
- Commit 'review: request type validation' and push to ${GIT_REPO_URL}
- Report REVISION_NEEDED

**Phase 3 - Fix (alice)** — after bob reports REVISION_NEEDED:
- Update src/math_utils.py on '${FEATURE_BRANCH}': raise TypeError if inputs are not int or float
- Commit 'fix: add type validation' and push to ${GIT_REPO_URL}
- Report PHASE3_DONE

**Phase 4 - Testing (charlie)** — after alice reports PHASE3_DONE:
- Clone ${GIT_REPO_URL}, create '${TEST_BRANCH}' from '${FEATURE_BRANCH}'
- Add 'tests/test_math_utils.py' with unit tests for add() and multiply(), including TypeError cases
- Commit 'test: add math utils unit tests' and push to ${GIT_REPO_URL}
- Report PHASE4_DONE

Report to me when all 4 phases complete."

# Snapshot before first LLM interaction
METRICS_BASELINE=$(snapshot_baseline "alice" "bob" "charlie")

matrix_send_message "${ADMIN_TOKEN}" "${DM_ROOM}" "${TASK_DESCRIPTION}"

log_info "Waiting for Manager to acknowledge and start coordination..."
REPLY=$(matrix_wait_for_reply "${ADMIN_TOKEN}" "${DM_ROOM}" "@manager" 300)

if [ -n "${REPLY}" ]; then
    log_pass "Manager acknowledged the git collaboration task"
else
    log_info "No explicit acknowledgment (Manager may have started processing directly)"
fi

log_section "Wait for Workflow Completion (up to 8 minutes)"

log_info "Waiting for all 4 phases to complete..."
sleep 480

MESSAGES=$(matrix_read_messages "${ADMIN_TOKEN}" "${DM_ROOM}" 100)
MSG_BODIES=$(echo "${MESSAGES}" | jq -r '[.chunk[].content.body] | join("\n---\n")' 2>/dev/null)

log_section "Verify Phase Results via Git"

# Phase 1: alice's feature branch has math_utils.py
MATH_UTILS=$(docker exec "${TEST_MANAGER_CONTAINER}" \
    git -C "${REPO_PATH}.git" show "${FEATURE_BRANCH}:src/math_utils.py" 2>/dev/null)
assert_not_empty "${MATH_UTILS}" "Phase 1: src/math_utils.py exists on ${FEATURE_BRANCH}"
assert_contains_i "${MATH_UTILS}" "def add" "Phase 1: add() function present"
assert_contains_i "${MATH_UTILS}" "def multiply" "Phase 1: multiply() function present"

# Phase 2: bob's review branch has review file
REVIEW=$(docker exec "${TEST_MANAGER_CONTAINER}" \
    git -C "${REPO_PATH}.git" show "${REVIEW_BRANCH}:reviews/math-utils-review.md" 2>/dev/null)
assert_not_empty "${REVIEW}" "Phase 2: reviews/math-utils-review.md exists on ${REVIEW_BRANCH}"
assert_contains_i "${REVIEW}" "validation" "Phase 2: review mentions validation"

# Phase 3: alice's updated branch has type validation
UPDATED_UTILS=$(docker exec "${TEST_MANAGER_CONTAINER}" \
    git -C "${REPO_PATH}.git" show "${FEATURE_BRANCH}:src/math_utils.py" 2>/dev/null)
assert_contains_i "${UPDATED_UTILS}" "TypeError" "Phase 3: type validation added to math_utils.py"

# Phase 4: charlie's test branch has test file
TESTS=$(docker exec "${TEST_MANAGER_CONTAINER}" \
    git -C "${REPO_PATH}.git" show "${TEST_BRANCH}:tests/test_math_utils.py" 2>/dev/null)
assert_not_empty "${TESTS}" "Phase 4: tests/test_math_utils.py exists on ${TEST_BRANCH}"
assert_contains_i "${TESTS}" "assert\|assertEqual\|test_" "Phase 4: test file contains assertions"

# Also check Matrix messages for phase reports
if echo "${MSG_BODIES}" | grep -qi "PHASE1_DONE\|phase 1"; then
    log_pass "Phase 1 completion reported in Matrix"
fi
if echo "${MSG_BODIES}" | grep -qi "REVISION_NEEDED\|revision"; then
    log_pass "Phase 2 review reported in Matrix"
fi
if echo "${MSG_BODIES}" | grep -qi "PHASE3_DONE\|phase 3"; then
    log_pass "Phase 3 fix reported in Matrix"
fi
if echo "${MSG_BODIES}" | grep -qi "PHASE4_DONE\|phase 4"; then
    log_pass "Phase 4 tests reported in Matrix"
fi

log_section "Collect Metrics"

wait_for_session_stable 5 60
METRICS=$(collect_delta_metrics "14-git-collab" "$METRICS_BASELINE" "alice" "bob" "charlie")
save_metrics_file "$METRICS" "14-git-collab"
print_metrics_report "$METRICS"

log_section "Cleanup"

# Stop git daemon
docker exec "${TEST_MANAGER_CONTAINER}" bash -c "
    if [ -f /tmp/git-daemon.pid ]; then
        kill \$(cat /tmp/git-daemon.pid) 2>/dev/null || true
        rm -f /tmp/git-daemon.pid
    fi
" 2>/dev/null || true
docker exec "${TEST_MANAGER_CONTAINER}" rm -rf "${REPO_PATH}.git" 2>/dev/null || true
log_info "Removed bare git repo and stopped git daemon"

test_teardown "14-git-collab"
test_summary
