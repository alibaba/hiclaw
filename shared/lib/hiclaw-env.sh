#!/bin/bash
# hiclaw-env.sh - Unified environment bootstrap for HiClaw scripts
#
# Single source of truth for both Manager and Worker containers.
# Source this file instead of manually setting up Matrix/storage variables.
#
# Provides:
#   HICLAW_RUNTIME         — "aliyun" | "docker" | "none"
#   HICLAW_MATRIX_SERVER   — Matrix server URL (works in both local and cloud)
#   HICLAW_STORAGE_BUCKET  — bucket name for mc commands
#   HICLAW_STORAGE_PREFIX  — "hiclaw/<bucket>" ready for mc paths
#   ensure_mc_credentials  — callable function (no-op in local mode)
#
# Usage:
#   source /opt/hiclaw/scripts/lib/hiclaw-env.sh

# ── Optional dependencies ─────────────────────────────────────────────────────
# base.sh provides log(), waitForService(), generateKey() — Manager-only.
# Worker images don't ship base.sh; the silent fallback is intentional.
source /opt/hiclaw/scripts/lib/base.sh 2>/dev/null || true

# ── Runtime detection ─────────────────────────────────────────────────────────
# Respect pre-set HICLAW_RUNTIME (e.g. from Dockerfile.aliyun ENV), only detect if unset
if [ -z "${HICLAW_RUNTIME:-}" ]; then
    if [ -n "${ALIBABA_CLOUD_OIDC_TOKEN_FILE:-}" ] && \
       [ -f "${ALIBABA_CLOUD_OIDC_TOKEN_FILE:-/nonexistent}" ]; then
        HICLAW_RUNTIME="aliyun"
    elif [ -S "${HICLAW_CONTAINER_SOCKET:-/var/run/docker.sock}" ]; then
        HICLAW_RUNTIME="docker"
    else
        HICLAW_RUNTIME="none"
    fi
fi

# ── Normalized variables ──────────────────────────────────────────────────────
# Matrix server: cloud mode uses external NLB address, local uses localhost
HICLAW_MATRIX_SERVER="${HICLAW_MATRIX_URL:-http://127.0.0.1:6167}"

# Matrix provider (tuwunel or synapse — both listen on same port 6167)
HICLAW_MATRIX_PROVIDER="${HICLAW_MATRIX_PROVIDER:-tuwunel}"

# AI Gateway: cloud mode uses env endpoint (HICLAW_AI_GATEWAY_URL), local uses domain:8080
HICLAW_AI_GATEWAY_SERVER="${HICLAW_AI_GATEWAY_URL:-http://${HICLAW_AI_GATEWAY_DOMAIN:-aigw-local.hiclaw.io}:8080}"

# Storage: cloud mode uses OSS bucket name, local uses MinIO default
HICLAW_STORAGE_BUCKET="${HICLAW_OSS_BUCKET:-hiclaw-storage}"
HICLAW_STORAGE_PREFIX="hiclaw/${HICLAW_STORAGE_BUCKET}"

# ── Credential management ────────────────────────────────────────────────────
# In cloud mode, provides ensure_mc_credentials() for STS token refresh.
# In local mode, ensure_mc_credentials() is a no-op.
source /opt/hiclaw/scripts/lib/oss-credentials.sh 2>/dev/null || true

# Embedding model: default to Qwen3-Embedding (text-embedding-v4), overridable via env.
# Use - (not :-) so HICLAW_EMBEDDING_MODEL="" in env file means "disabled" instead of falling back to default.
HICLAW_EMBEDDING_MODEL="${HICLAW_EMBEDDING_MODEL-text-embedding-v4}"

export HICLAW_RUNTIME HICLAW_MATRIX_SERVER HICLAW_MATRIX_PROVIDER HICLAW_AI_GATEWAY_SERVER HICLAW_STORAGE_BUCKET HICLAW_STORAGE_PREFIX HICLAW_EMBEDDING_MODEL

# ── Matrix user registration ─────────────────────────────────────────────────
# Provider-aware registration: Tuwunel uses registration_token, Synapse uses
# shared-secret HMAC via /_synapse/admin/v1/register.

# Register a Matrix user (silent — logs on failure, no stdout on success).
# Usage: matrix_register_user <username> <password>
matrix_register_user() {
    local username="$1"
    local password="$2"
    local resp
    resp=$(matrix_register_user_raw "${username}" "${password}" 2>&1) || true
    if echo "${resp}" | jq -e '.access_token' > /dev/null 2>&1; then
        return 0
    fi
    local errcode
    errcode=$(echo "${resp}" | jq -r '.errcode // empty' 2>/dev/null)
    if [ "${errcode}" = "M_USER_IN_USE" ]; then
        { type log >/dev/null 2>&1 && log "Account ${username} already exists" || echo "[hiclaw] Account ${username} already exists"; }
        return 0
    fi
    { type log >/dev/null 2>&1 && log "WARNING: Failed to register ${username}: ${resp}" || echo "[hiclaw] WARNING: Failed to register ${username}: ${resp}"; }
    return 1
}

# Register a Matrix user and return the raw JSON response.
# Usage: matrix_register_user_raw <username> <password>
# Returns: JSON response from the registration endpoint
matrix_register_user_raw() {
    local username="$1"
    local password="$2"
    local provider="${HICLAW_MATRIX_PROVIDER:-tuwunel}"

    if [ "${provider}" = "synapse" ]; then
        _matrix_register_synapse "${username}" "${password}"
    else
        _matrix_register_tuwunel "${username}" "${password}"
    fi
}

# Internal: Tuwunel registration via registration_token
_matrix_register_tuwunel() {
    local username="$1"
    local password="$2"
    curl -s -X POST "${HICLAW_MATRIX_SERVER}/_matrix/client/v3/register" \
        -H 'Content-Type: application/json' \
        -d '{
            "username": "'"${username}"'",
            "password": "'"${password}"'",
            "auth": {
                "type": "m.login.registration_token",
                "token": "'"${HICLAW_REGISTRATION_TOKEN}"'"
            }
        }'
}

# Internal: Synapse registration via shared-secret HMAC (/_synapse/admin/v1/register)
_matrix_register_synapse() {
    local username="$1"
    local password="$2"
    local shared_secret="${HICLAW_SYNAPSE_SHARED_SECRET}"

    if [ -z "${shared_secret}" ]; then
        echo "[hiclaw] ERROR: HICLAW_SYNAPSE_SHARED_SECRET not set" >&2
        return 1
    fi

    # Step 1: Get nonce
    local nonce_resp nonce
    nonce_resp=$(curl -s "${HICLAW_MATRIX_SERVER}/_synapse/admin/v1/register") || return 1
    nonce=$(echo "${nonce_resp}" | jq -r '.nonce') || return 1
    [ -z "${nonce}" ] || [ "${nonce}" = "null" ] && return 1

    # Step 2: Compute HMAC-SHA1
    # Format: nonce\0username\0password\0notadmin
    local mac
    mac=$(printf '%s\0%s\0%s\0notadmin' "${nonce}" "${username}" "${password}" \
        | openssl dgst -sha1 -hmac "${shared_secret}" 2>/dev/null \
        | sed 's/^.* //') || return 1

    # Step 3: Register
    curl -s -X POST "${HICLAW_MATRIX_SERVER}/_synapse/admin/v1/register" \
        -H 'Content-Type: application/json' \
        -d '{
            "nonce": "'"${nonce}"'",
            "username": "'"${username}"'",
            "password": "'"${password}"'",
            "mac": "'"${mac}"'",
            "admin": false
        }'
}
