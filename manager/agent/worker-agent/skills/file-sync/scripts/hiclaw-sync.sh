#!/bin/sh
# hiclaw-sync.sh - Pull latest config from centralized storage
# Called by the Worker agent when coordinator notifies of config updates.
# Uses /root/hiclaw-fs/ layout — same absolute path as the Manager's MinIO mirror.

# Bootstrap env: provides HICLAW_STORAGE_PREFIX and ensure_mc_credentials
if [ -f /opt/hiclaw/scripts/lib/hiclaw-env.sh ]; then
    . /opt/hiclaw/scripts/lib/hiclaw-env.sh
else
    . /opt/hiclaw/scripts/lib/oss-credentials.sh 2>/dev/null || true
    ensure_mc_credentials 2>/dev/null || true
    HICLAW_STORAGE_PREFIX="hiclaw/${HICLAW_OSS_BUCKET:-hiclaw-storage}"
fi

# Merge helper for openclaw.json (remote base + local Worker additions)
. /opt/hiclaw/scripts/lib/merge-openclaw-config.sh

WORKER_NAME="${HICLAW_WORKER_NAME:?HICLAW_WORKER_NAME is required}"
HICLAW_ROOT="/root/hiclaw-fs"
WORKSPACE="${HICLAW_ROOT}/agents/${WORKER_NAME}"

ensure_mc_credentials 2>/dev/null || true

# Save local openclaw.json before mirror overwrites it
LOCAL_OPENCLAW="${WORKSPACE}/openclaw.json"
SAVED_LOCAL="/tmp/openclaw-local-sync.json"
LOCAL_SYNC_CUTOFF_FILE="/tmp/hiclaw-local-sync-${WORKER_NAME}.stamp"
if [ -f "${LOCAL_OPENCLAW}" ]; then
    cp "${LOCAL_OPENCLAW}" "${SAVED_LOCAL}"
fi

# Runtime state is local-only. Pulling it back from MinIO creates churn without
# helping task durability, so only sync user-managed workspace files.
mc mirror "${HICLAW_STORAGE_PREFIX}/agents/${WORKER_NAME}/" "${WORKSPACE}/" --overwrite \
    --exclude ".agents/**" \
    --exclude ".cache/**" \
    --exclude ".codex-agent/ready" \
    --exclude ".codex-home/**" \
    --exclude "credentials/**" \
    --exclude ".local/**" \
    --exclude ".mc/**" \
    --exclude ".mc.bin/**" \
    --exclude ".npm/**" \
    --exclude "*.lock" \
    --exclude ".openclaw/agents/**" \
    --exclude ".openclaw/canvas/**" \
    --exclude ".openclaw/matrix/**" 2>&1
mc mirror "${HICLAW_STORAGE_PREFIX}/shared/" "${HICLAW_ROOT}/shared/" --overwrite 2>/dev/null || true
touch "${LOCAL_SYNC_CUTOFF_FILE}"

# Merge openclaw.json: remote (MinIO, now in workspace) as base + local Worker additions
if [ -f "${SAVED_LOCAL}" ] && [ -f "${LOCAL_OPENCLAW}" ]; then
    merge_openclaw_config "${LOCAL_OPENCLAW}" "${SAVED_LOCAL}"
    rm -f "${SAVED_LOCAL}"
fi

# Restore +x on scripts (MinIO does not preserve Unix permission bits)
find "${WORKSPACE}/skills" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

echo "Config sync completed at $(date)"
