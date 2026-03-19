#!/bin/bash
# hiclaw-verify.sh - Post-install shallow verification for HiClaw
#
# Usage:
#   bash install/hiclaw-verify.sh [container_name]   # default: hiclaw-manager
#
# Runs 6 read-only reachability checks and prints PASS/FAIL per check.
# Exit code: 0 if all pass, 1 if any fail.

# No set -e: each check is independent; failures do not abort subsequent checks.

CONTAINER="${1:-hiclaw-manager}"

# ---------- Docker/Podman detection ----------

DOCKER_CMD="docker"
if ! docker version >/dev/null 2>&1; then
    if podman version >/dev/null 2>&1; then
        DOCKER_CMD="podman"
    fi
fi

# ---------- Port/config detection from container env ----------

container_env=$("${DOCKER_CMD}" exec "${CONTAINER}" printenv 2>/dev/null) || container_env=""
PORT_GATEWAY=$(echo "$container_env" | grep ^HICLAW_PORT_GATEWAY= | cut -d= -f2-)
PORT_CONSOLE=$(echo "$container_env" | grep ^HICLAW_PORT_CONSOLE= | cut -d= -f2-)
PORT_GATEWAY="${PORT_GATEWAY:-18080}"
PORT_CONSOLE="${PORT_CONSOLE:-18001}"

# ---------- Result tracking ----------

PASS=0
FAIL=0

check_pass() {
    echo "  [PASS] $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo "  [FAIL] $1"
    FAIL=$((FAIL + 1))
}

# ---------- Checks ----------

echo ""
echo "==> HiClaw Post-Install Verification"

# 1. Manager container running
if "${DOCKER_CMD}" ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
    check_pass "Manager container running"
else
    check_fail "Manager container running (container '${CONTAINER}' not found in docker ps)"
fi

# 2. MinIO health check (internal via docker exec)
minio_status=$("${DOCKER_CMD}" exec "${CONTAINER}" \
    curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    "http://127.0.0.1:9000/minio/health/live" 2>/dev/null) || minio_status="000"
if [ "${minio_status}" = "200" ]; then
    check_pass "MinIO health check"
else
    check_fail "MinIO health check (HTTP ${minio_status})"
fi

# 3. Matrix API reachable (internal via docker exec)
matrix_status=$("${DOCKER_CMD}" exec "${CONTAINER}" \
    curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    "http://127.0.0.1:6167/_matrix/client/versions" 2>/dev/null) || matrix_status="000"
if [ "${matrix_status}" = "200" ]; then
    check_pass "Matrix API reachable"
else
    check_fail "Matrix API reachable (HTTP ${matrix_status})"
fi

# 4. Higress Gateway reachable (external host port, any non-000 response is ok)
gateway_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    "http://127.0.0.1:${PORT_GATEWAY}/" 2>/dev/null) || gateway_status="000"
if [ "${gateway_status}" != "000" ]; then
    check_pass "Higress Gateway reachable"
else
    check_fail "Higress Gateway reachable (no response on port ${PORT_GATEWAY})"
fi

# 5. Higress Console reachable (external host port, HTTP 200)
console_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    "http://127.0.0.1:${PORT_CONSOLE}/" 2>/dev/null) || console_status="000"
if [ "${console_status}" = "200" ]; then
    check_pass "Higress Console reachable"
else
    check_fail "Higress Console reachable (HTTP ${console_status} on port ${PORT_CONSOLE})"
fi

# 6. OpenClaw Agent healthy (internal via docker exec)
agent_output=$("${DOCKER_CMD}" exec "${CONTAINER}" \
    openclaw gateway health --json 2>/dev/null) || agent_output=""
if echo "${agent_output}" | grep -q '"ok"'; then
    check_pass "OpenClaw Agent healthy"
else
    check_fail "OpenClaw Agent healthy (output: ${agent_output:-<empty>})"
fi

# ---------- Summary ----------

TOTAL=$((PASS + FAIL))
echo "==> Result: ${PASS}/${TOTAL} passed"
echo ""

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
