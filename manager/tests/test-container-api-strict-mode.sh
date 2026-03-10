#!/bin/bash
# test-container-api-strict-mode.sh
# Regression tests for container-api.sh when sourced from strict-mode scripts.
#
# Usage: bash manager/tests/test-container-api-strict-mode.sh

set -euo pipefail

PASS=0
FAIL=0
TMPDIR_ROOT=$(mktemp -d)
SERVER_PID=""
SOCKET_PATH=""
trap 'if [ -n "${SERVER_PID}" ]; then kill "${SERVER_PID}" 2>/dev/null || true; fi; rm -rf "${TMPDIR_ROOT}"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../scripts/lib/container-api.sh"

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "       expected: $2"; echo "       got:      $3"; FAIL=$((FAIL + 1)); }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "${expected}" = "${actual}" ]; then
        pass "${desc}"
    else
        fail "${desc}" "${expected}" "${actual}"
    fi
}

start_fake_container_api() {
    SOCKET_PATH="${TMPDIR_ROOT}/docker.sock"
    SOCKET_PATH="${SOCKET_PATH}" python3 - <<'PY' &
import json
import os
import socket

sock_path = os.environ['SOCKET_PATH']
try:
    os.unlink(sock_path)
except FileNotFoundError:
    pass

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(5)

responses = {
    '/version': ('200 OK', {'ApiVersion': '1.47'}),
    '/containers/test-worker/start': ('204 No Content', None),
}

while True:
    conn, _ = server.accept()
    try:
        data = b''
        while b'\r\n\r\n' not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        line = data.split(b'\r\n', 1)[0].decode('utf-8', 'replace')
        parts = line.split()
        path = parts[1] if len(parts) >= 2 else '/'
        status, body = responses.get(path, ('404 Not Found', {'error': path}))
        if body is None:
            payload = b''
        else:
            payload = json.dumps(body).encode('utf-8')
        headers = [
            f'HTTP/1.1 {status}',
            'Content-Type: application/json',
            f'Content-Length: {len(payload)}',
            '',
            ''
        ]
        conn.sendall('\r\n'.join(headers).encode('utf-8') + payload)
    finally:
        conn.close()
PY
    SERVER_PID=$!

    for _ in $(seq 1 50); do
        [ -S "${SOCKET_PATH}" ] && return 0
        sleep 0.1
    done

    echo "Fake container API did not create socket in time" >&2
    exit 1
}

run_strict_script() {
    local script_body="$1"
    HICLAW_CONTAINER_SOCKET="${SOCKET_PATH}" bash -euo pipefail -c "source '${LIB_PATH}'; ${script_body}"
}

echo ""
echo "=== TC1: container_api_available works in strict mode ==="
start_fake_container_api
result=$(run_strict_script 'if container_api_available; then echo ok; else echo fail; fi' 2>&1 || true)
assert_eq "strict mode availability check" "ok" "${result}"


echo ""
echo "=== TC2: _api_code helper tolerates omitted data arg in strict mode ==="
result=$(run_strict_script 'container_name=test-worker; code=$(_api_code POST "/containers/${container_name}/start"); echo "$code"' 2>&1 || true)
assert_eq "strict mode _api_code without request body" "204" "${result}"


echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
