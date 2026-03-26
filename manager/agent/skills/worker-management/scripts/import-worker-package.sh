#!/bin/bash
# import-worker-package.sh - Preload a Worker template into the Manager workspace
#
# This prepares /root/hiclaw-fs/agents/<worker>/ before create-worker.sh runs.
# Supported package inputs:
#   - ZIP file containing manifest.json + config/ + skills/
#   - Directory downloaded by nacos-cli agentspec-get

set -euo pipefail

log() {
    echo "[hiclaw $(date '+%Y-%m-%d %H:%M:%S')] $1"
}

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

WORKER_NAME=""
PACKAGE_PATH=""
WORKER_RUNTIME="${HICLAW_DEFAULT_WORKER_RUNTIME:-openclaw}"
WORKER_ROLE="worker"

while [ $# -gt 0 ]; do
    case "$1" in
        --worker) WORKER_NAME="$2"; shift 2 ;;
        --package) PACKAGE_PATH="$2"; shift 2 ;;
        --runtime) WORKER_RUNTIME="$2"; shift 2 ;;
        --role) WORKER_ROLE="$2"; shift 2 ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[ -n "${WORKER_NAME}" ] || fail "--worker is required"
[ -n "${PACKAGE_PATH}" ] || fail "--package is required"
[ -e "${PACKAGE_PATH}" ] || fail "package not found: ${PACKAGE_PATH}"

TMP_DIR=$(mktemp -d /tmp/hiclaw-worker-package-XXXXXX)
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

SRC_DIR=""
if [ -d "${PACKAGE_PATH}" ]; then
    SRC_DIR="${PACKAGE_PATH}"
else
    SRC_DIR="${TMP_DIR}/package"
    mkdir -p "${SRC_DIR}"
    unzip -q "${PACKAGE_PATH}" -d "${SRC_DIR}"
fi

MANIFEST_FILE="${SRC_DIR}/manifest.json"
[ -f "${MANIFEST_FILE}" ] || fail "manifest.json not found in package: ${PACKAGE_PATH}"

TARGET_DIR="/root/hiclaw-fs/agents/${WORKER_NAME}"
mkdir -p "${TARGET_DIR}"

_builtin_agent_root="/opt/hiclaw/agent/worker-agent"
if [ "${WORKER_ROLE}" = "team_leader" ] && [ -d "/opt/hiclaw/agent/team-leader-agent" ]; then
    _builtin_agent_root="/opt/hiclaw/agent/team-leader-agent"
elif [ "${WORKER_RUNTIME}" = "copaw" ] && [ -d "/opt/hiclaw/agent/copaw-worker-agent" ]; then
    _builtin_agent_root="/opt/hiclaw/agent/copaw-worker-agent"
fi

if [ -f "${SRC_DIR}/config/SOUL.md" ]; then
    cp "${SRC_DIR}/config/SOUL.md" "${TARGET_DIR}/SOUL.md"
    log "Imported SOUL.md for ${WORKER_NAME}"
elif [ ! -f "${TARGET_DIR}/SOUL.md" ]; then
    cat > "${TARGET_DIR}/SOUL.md" <<EOF
# ${WORKER_NAME} - Worker Agent

## AI Identity

**You are an AI Agent, not a human.**

## Role
- Name: ${WORKER_NAME}
- Specialization: Imported Worker template
EOF
    log "Generated fallback SOUL.md for ${WORKER_NAME}"
fi

if [ -f "${SRC_DIR}/config/AGENTS.md" ]; then
    source /opt/hiclaw/scripts/lib/builtin-merge.sh
    TMP_AGENTS="${TMP_DIR}/AGENTS.md"
    update_builtin_section "${TMP_AGENTS}" "${_builtin_agent_root}/AGENTS.md"
    # Guard: update_builtin_section returns 0 even when source is missing, leaving TMP_AGENTS
    # without builtin markers. Without markers, create-worker.sh's update_builtin_section_minio
    # would treat the file as a legacy install and discard the custom AGENTS.md content.
    if ! grep -q 'hiclaw-builtin-start' "${TMP_AGENTS}" 2>/dev/null; then
        log "WARNING: builtin AGENTS.md not found at ${_builtin_agent_root}/AGENTS.md; skipping AGENTS.md import"
    else
        printf '\n' >> "${TMP_AGENTS}"
        cat "${SRC_DIR}/config/AGENTS.md" >> "${TMP_AGENTS}"
        cp "${TMP_AGENTS}" "${TARGET_DIR}/AGENTS.md"
        log "Imported AGENTS.md for ${WORKER_NAME}"
    fi
fi

if [ -f "${SRC_DIR}/config/MEMORY.md" ]; then
    cp "${SRC_DIR}/config/MEMORY.md" "${TARGET_DIR}/MEMORY.md"
    log "Imported MEMORY.md for ${WORKER_NAME}"
fi

if [ -d "${SRC_DIR}/config/memory" ]; then
    mkdir -p "${TARGET_DIR}/memory"
    cp -R "${SRC_DIR}/config/memory/." "${TARGET_DIR}/memory/"
    log "Imported memory files for ${WORKER_NAME}"
fi

if [ -d "${SRC_DIR}/skills" ]; then
    find "${SRC_DIR}/skills" -mindepth 1 -maxdepth 1 -type d | while read -r skill_dir; do
        skill_name=$(basename "${skill_dir}")
        mkdir -p "${TARGET_DIR}/custom-skills/${skill_name}"
        cp -R "${skill_dir}/." "${TARGET_DIR}/custom-skills/${skill_name}/"
        log "Imported custom skill ${skill_name} for ${WORKER_NAME}"
    done
fi

if [ -d "${SRC_DIR}/crons" ]; then
    mkdir -p "${TARGET_DIR}/crons"
    cp -R "${SRC_DIR}/crons/." "${TARGET_DIR}/crons/"
    log "Imported cron config for ${WORKER_NAME}"
fi

log "Worker package import complete for ${WORKER_NAME}"
