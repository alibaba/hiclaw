#!/bin/bash
# cloud-manager-entrypoint.sh - Cloud Manager Agent startup for FC
#
# Connects to external services:
#   - Tuwunel (Matrix) via NLB private address
#   - AI Gateway for LLM access
#   - OSS via mc (S3-compatible) for file storage
#
# Required env vars:
#   HICLAW_MATRIX_URL          - Tuwunel NLB address (e.g. http://nlb-xxx:6167)
#   HICLAW_MATRIX_DOMAIN       - Matrix server_name (e.g. hiclaw.cloud)
#   HICLAW_AI_GATEWAY_URL      - AI Gateway URL (e.g. http://nlb-xxx)
#   HICLAW_MANAGER_GATEWAY_KEY - Manager consumer API key for AI Gateway
#   HICLAW_REGISTRATION_TOKEN  - Tuwunel registration token
#   HICLAW_ADMIN_USER          - Human admin Matrix username
#   HICLAW_ADMIN_PASSWORD      - Human admin password
#   HICLAW_OSS_ENDPOINT        - OSS S3-compatible endpoint (for mc mirror)
#   HICLAW_OSS_BUCKET          - OSS bucket name
#   HICLAW_REGION              - Alibaba Cloud region (for STS endpoint)
#
# RRSA OIDC env vars (auto-injected by SAE when RRSA is enabled):
#   ALIBABA_CLOUD_OIDC_TOKEN_FILE   - Path to OIDC token file
#   ALIBABA_CLOUD_ROLE_ARN          - RAM Role ARN
#   ALIBABA_CLOUD_OIDC_PROVIDER_ARN - OIDC Provider ARN

set -e

log() {
    echo "[cloud-manager $(date '+%Y-%m-%d %H:%M:%S')] $1"
}

generateKey() {
    openssl rand -hex "${1:-16}"
}

# ============================================================
# Step 0: Set timezone
# ============================================================
if [ -n "${TZ}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "${TZ}" > /etc/timezone
    log "Timezone set to ${TZ}"
fi

# ============================================================
# Step 1: Validate required environment variables
# ============================================================
HICLAW_MATRIX_URL="${HICLAW_MATRIX_URL:?HICLAW_MATRIX_URL is required}"
HICLAW_MATRIX_DOMAIN="${HICLAW_MATRIX_DOMAIN:?HICLAW_MATRIX_DOMAIN is required}"
HICLAW_AI_GATEWAY_URL="${HICLAW_AI_GATEWAY_URL:?HICLAW_AI_GATEWAY_URL is required}"
HICLAW_MANAGER_GATEWAY_KEY="${HICLAW_MANAGER_GATEWAY_KEY:?HICLAW_MANAGER_GATEWAY_KEY is required}"
HICLAW_REGISTRATION_TOKEN="${HICLAW_REGISTRATION_TOKEN:?HICLAW_REGISTRATION_TOKEN is required}"
HICLAW_ADMIN_USER="${HICLAW_ADMIN_USER:?HICLAW_ADMIN_USER is required}"
HICLAW_ADMIN_PASSWORD="${HICLAW_ADMIN_PASSWORD:?HICLAW_ADMIN_PASSWORD is required}"
HICLAW_OSS_BUCKET="${HICLAW_OSS_BUCKET:-hiclaw-cloud-storage}"

HICLAW_DEFAULT_MODEL="${HICLAW_DEFAULT_MODEL:-qwen-plus}"

log "Cloud Manager starting..."
log "  Matrix URL: ${HICLAW_MATRIX_URL}"
log "  Matrix Domain: ${HICLAW_MATRIX_DOMAIN}"
log "  AI Gateway: ${HICLAW_AI_GATEWAY_URL}"
log "  OSS Bucket: ${HICLAW_OSS_BUCKET}"
log "  Model: ${HICLAW_DEFAULT_MODEL}"

# ============================================================
# Step 2: Configure mc alias for OSS (RRSA OIDC)
# ============================================================
ALIBABA_CLOUD_OIDC_TOKEN_FILE="${ALIBABA_CLOUD_OIDC_TOKEN_FILE:?ALIBABA_CLOUD_OIDC_TOKEN_FILE is required (enable RRSA OIDC on SAE)}"
ALIBABA_CLOUD_ROLE_ARN="${ALIBABA_CLOUD_ROLE_ARN:?ALIBABA_CLOUD_ROLE_ARN is required (enable RRSA OIDC on SAE)}"
ALIBABA_CLOUD_OIDC_PROVIDER_ARN="${ALIBABA_CLOUD_OIDC_PROVIDER_ARN:?ALIBABA_CLOUD_OIDC_PROVIDER_ARN is required (enable RRSA OIDC on SAE)}"
HICLAW_REGION="${HICLAW_REGION:-cn-hangzhou}"

log "Configuring mc with RRSA OIDC credentials (lazy-refresh via oss-credentials.sh)..."
source /opt/hiclaw/scripts/lib/oss-credentials.sh
ensure_mc_credentials || { log "FATAL: Initial STS credential fetch failed"; exit 1; }

# ============================================================
# Step 3: Wait for Tuwunel to be ready
# ============================================================
log "Waiting for Tuwunel Matrix server..."
RETRY=0
while [ "${RETRY}" -lt 30 ]; do
    if curl -sf "${HICLAW_MATRIX_URL}/_matrix/client/versions" > /dev/null 2>&1; then
        log "Tuwunel is ready"
        break
    fi
    RETRY=$((RETRY + 1))
    log "  Waiting for Tuwunel (attempt ${RETRY}/30)..."
    sleep 5
done
if [ "${RETRY}" -ge 30 ]; then
    log "ERROR: Tuwunel not reachable at ${HICLAW_MATRIX_URL}"
    exit 1
fi

# ============================================================
# Step 4: Register Matrix users and obtain token
# ============================================================
# Auto-generate manager password if not provided
HICLAW_MANAGER_PASSWORD="${HICLAW_MANAGER_PASSWORD:-$(generateKey 16)}"

log "Registering human admin Matrix account..."
curl -sf -X POST "${HICLAW_MATRIX_URL}/_matrix/client/v3/register" \
    -H 'Content-Type: application/json' \
    -d '{
        "username": "'"${HICLAW_ADMIN_USER}"'",
        "password": "'"${HICLAW_ADMIN_PASSWORD}"'",
        "auth": {
            "type": "m.login.registration_token",
            "token": "'"${HICLAW_REGISTRATION_TOKEN}"'"
        }
    }' > /dev/null 2>&1 || log "Admin account may already exist"

log "Registering Manager Agent Matrix account..."
curl -sf -X POST "${HICLAW_MATRIX_URL}/_matrix/client/v3/register" \
    -H 'Content-Type: application/json' \
    -d '{
        "username": "manager",
        "password": "'"${HICLAW_MANAGER_PASSWORD}"'",
        "auth": {
            "type": "m.login.registration_token",
            "token": "'"${HICLAW_REGISTRATION_TOKEN}"'"
        }
    }' > /dev/null 2>&1 || log "Manager account may already exist"

log "Obtaining Manager Matrix access token..."
_LOGIN_RESPONSE=$(curl -sf -X POST "${HICLAW_MATRIX_URL}/_matrix/client/v3/login" \
    -H 'Content-Type: application/json' \
    -d '{
        "type": "m.login.password",
        "identifier": {"type": "m.id.user", "user": "manager"},
        "password": "'"${HICLAW_MANAGER_PASSWORD}"'"
    }' 2>&1)

MANAGER_MATRIX_TOKEN=$(echo "${_LOGIN_RESPONSE}" | jq -r '.access_token' 2>/dev/null)
if [ -z "${MANAGER_MATRIX_TOKEN}" ] || [ "${MANAGER_MATRIX_TOKEN}" = "null" ]; then
    log "ERROR: Failed to obtain Manager Matrix token"
    log "Response: ${_LOGIN_RESPONSE}"
    exit 1
fi
log "Manager Matrix token obtained (prefix: ${MANAGER_MATRIX_TOKEN:0:10}...)"
export MANAGER_MATRIX_TOKEN

# ============================================================
# Step 4.5: Create admin DM room and schedule welcome message
# ============================================================
# Mirrors the logic in install/hiclaw-install.sh send_welcome_message().
# 1. Admin logs in to Matrix
# 2. Find or create a DM room with Manager (idempotent)
# 3. If first boot (no soul-configured), launch background process to
#    wait for Manager to join and send the onboarding welcome message.

MANAGER_FULL_ID="@manager:${HICLAW_MATRIX_DOMAIN}"
ADMIN_FULL_ID="@${HICLAW_ADMIN_USER}:${HICLAW_MATRIX_DOMAIN}"

log "Logging in as admin to create DM room..."
_ADMIN_LOGIN=$(curl -sf -X POST "${HICLAW_MATRIX_URL}/_matrix/client/v3/login" \
    -H 'Content-Type: application/json' \
    -d '{
        "type": "m.login.password",
        "identifier": {"type": "m.id.user", "user": "'"${HICLAW_ADMIN_USER}"'"},
        "password": "'"${HICLAW_ADMIN_PASSWORD}"'"
    }' 2>&1) || true

ADMIN_MATRIX_TOKEN=$(echo "${_ADMIN_LOGIN}" | jq -r '.access_token // empty' 2>/dev/null)
if [ -z "${ADMIN_MATRIX_TOKEN}" ]; then
    log "WARNING: Failed to login as admin, skipping DM room creation"
    log "Response: ${_ADMIN_LOGIN}"
else
    # Search for existing DM room with Manager (idempotent, same as local install)
    DM_ROOM_ID=""
    _JOINED_ROOMS=$(curl -sf "${HICLAW_MATRIX_URL}/_matrix/client/v3/joined_rooms" \
        -H "Authorization: Bearer ${ADMIN_MATRIX_TOKEN}" 2>/dev/null \
        | jq -r '.joined_rooms[]' 2>/dev/null) || true
    for _rid in ${_JOINED_ROOMS}; do
        _members=$(curl -sf "${HICLAW_MATRIX_URL}/_matrix/client/v3/rooms/${_rid}/members" \
            -H "Authorization: Bearer ${ADMIN_MATRIX_TOKEN}" 2>/dev/null \
            | jq -r '.chunk[].state_key' 2>/dev/null) || continue
        _count=$(echo "${_members}" | wc -l | xargs)
        if [ "${_count}" = "2" ] && echo "${_members}" | grep -q "@manager:"; then
            DM_ROOM_ID="${_rid}"
            break
        fi
    done

    if [ -n "${DM_ROOM_ID}" ]; then
        log "Existing DM room found: ${DM_ROOM_ID}"
    else
        log "Creating DM room with Manager..."
        _CREATE_RESP=$(curl -sf -X POST "${HICLAW_MATRIX_URL}/_matrix/client/v3/createRoom" \
            -H "Authorization: Bearer ${ADMIN_MATRIX_TOKEN}" \
            -H 'Content-Type: application/json' \
            -d "{\"is_direct\":true,\"invite\":[\"${MANAGER_FULL_ID}\"],\"preset\":\"trusted_private_chat\"}" 2>/dev/null) || true
        DM_ROOM_ID=$(echo "${_CREATE_RESP}" | jq -r '.room_id // empty' 2>/dev/null)
        if [ -n "${DM_ROOM_ID}" ]; then
            log "DM room created: ${DM_ROOM_ID}"
        else
            log "WARNING: Failed to create DM room: ${_CREATE_RESP}"
        fi
    fi

    # Schedule welcome message in background (only on first boot)
    # WORKSPACE is defined in Step 5 below; use the known path directly.
    if [ -n "${DM_ROOM_ID}" ] && [ ! -f "/root/manager-workspace/soul-configured" ]; then
        log "Scheduling welcome message (background, waiting for OpenClaw to start)..."
        (
            _HICLAW_LANGUAGE="${HICLAW_LANGUAGE:-zh}"
            _HICLAW_TIMEZONE="${TZ:-Asia/Shanghai}"

            # Wait for Manager to join the room (OpenClaw auto-joins on sync)
            _wait=0
            _joined=false
            while [ "${_wait}" -lt 120 ]; do
                _m=$(curl -sf "${HICLAW_MATRIX_URL}/_matrix/client/v3/rooms/${DM_ROOM_ID}/members" \
                    -H "Authorization: Bearer ${ADMIN_MATRIX_TOKEN}" 2>/dev/null \
                    | jq -r '.chunk[].state_key' 2>/dev/null) || true
                if echo "${_m}" | grep -q "${MANAGER_FULL_ID}"; then
                    _joined=true
                    break
                fi
                sleep 3
                _wait=$((_wait + 3))
            done

            if [ "${_joined}" != "true" ]; then
                log "WARNING: Manager did not join DM room within 120s, skipping welcome message"
                exit 0
            fi
            log "Manager joined DM room, sending welcome message..."

            _welcome_msg="This is an automated message from the HiClaw cloud deployment. This is a fresh installation.

--- Installation Context ---
User Language: ${_HICLAW_LANGUAGE}  (zh = Chinese, en = English)
User Timezone: ${_HICLAW_TIMEZONE}  (IANA timezone identifier)
---

You are an AI agent that manages a team of worker agents. Your identity and personality have not been configured yet — the human admin is about to meet you for the first time.

Please begin the onboarding conversation:

1. Greet the admin warmly and briefly describe what you can do (coordinate workers, manage tasks, run multi-agent projects) — without referring to yourself by any specific title yet
2. The user has selected \"${_HICLAW_LANGUAGE}\" as their preferred language during installation. Use this language for your greeting and all subsequent communication.
3. The user's timezone is ${_HICLAW_TIMEZONE}. Based on this timezone, you may infer their likely region and suggest additional language options (e.g., Japanese, Korean, German, etc.) that they might prefer for future interactions.
4. Ask them the following questions (one message is fine):
   a. What would they like to call you? (name or title)
   b. What communication style do they prefer? (e.g. formal, casual, concise, detailed)
   c. Any specific behavior guidelines or constraints they want you to follow?
   d. Confirm the default language they want you to use (offer alternatives based on timezone)
5. After they reply, write their preferences to the \"Identity & Personality\" section of ~/SOUL.md — replace the \"(not yet configured)\" placeholder with the configured identity
6. Confirm what you wrote, and ask if they would like to adjust anything
7. Once the admin confirms the identity is set, run: touch ~/soul-configured

The human admin will start chatting shortly."

            _txn_id="welcome-cloud-$(date +%s)"
            _payload=$(jq -nc --arg body "${_welcome_msg}" '{"msgtype":"m.text","body":$body}')
            curl -sf -X PUT "${HICLAW_MATRIX_URL}/_matrix/client/v3/rooms/${DM_ROOM_ID}/send/m.room.message/${_txn_id}" \
                -H "Authorization: Bearer ${ADMIN_MATRIX_TOKEN}" \
                -H 'Content-Type: application/json' \
                -d "${_payload}" > /dev/null 2>&1 \
                && log "Welcome message sent to DM room" \
                || log "WARNING: Failed to send welcome message"
        ) &
        log "Welcome message background process started (PID: $!)"
    elif [ -f "/root/manager-workspace/soul-configured" ]; then
        log "Soul already configured, skipping welcome message"
    fi
fi

# ============================================================
# Step 5: Initialize workspace from OSS or first boot
# ============================================================
WORKSPACE="/root/manager-workspace"
HICLAW_FS="/root/hiclaw-fs"
mkdir -p "${WORKSPACE}" "${HICLAW_FS}/shared" "${HICLAW_FS}/agents"

# Pull existing workspace from OSS if available
log "Pulling workspace from OSS..."
ensure_mc_credentials
mc mirror "hiclaw/${HICLAW_OSS_BUCKET}/manager/" "${WORKSPACE}/" --overwrite 2>/dev/null || true
mc mirror "hiclaw/${HICLAW_OSS_BUCKET}/shared/" "${HICLAW_FS}/shared/" --overwrite 2>/dev/null || true
mc mirror "hiclaw/${HICLAW_OSS_BUCKET}/agents/" "${HICLAW_FS}/agents/" --overwrite 2>/dev/null || true

# Initialize agent files from image (upgrade-builtins equivalent)
IMAGE_VERSION=$(cat /opt/hiclaw/agent/.builtin-version 2>/dev/null || echo "unknown")
INSTALLED_VERSION=$(cat "${WORKSPACE}/.builtin-version" 2>/dev/null || echo "")

if [ ! -f "${WORKSPACE}/.initialized" ] || [ "${IMAGE_VERSION}" != "${INSTALLED_VERSION}" ] || [ "${IMAGE_VERSION}" = "latest" ]; then
    log "Initializing/upgrading agent files (${INSTALLED_VERSION} -> ${IMAGE_VERSION})..."

    # Copy agent definitions to workspace
    cp -f /opt/hiclaw/agent/SOUL.md "${WORKSPACE}/SOUL.md"
    cp -f /opt/hiclaw/agent/AGENTS.md "${WORKSPACE}/AGENTS.md"
    cp -f /opt/hiclaw/agent/HEARTBEAT.md "${WORKSPACE}/HEARTBEAT.md"
    [ -f /opt/hiclaw/agent/TOOLS.md ] && cp -f /opt/hiclaw/agent/TOOLS.md "${WORKSPACE}/TOOLS.md"

    # Copy skills
    mkdir -p "${WORKSPACE}/skills"
    if [ -d /opt/hiclaw/agent/skills ]; then
        cp -rf /opt/hiclaw/agent/skills/* "${WORKSPACE}/skills/" 2>/dev/null || true
    fi

    # Copy worker-skills
    mkdir -p "${WORKSPACE}/worker-skills"
    if [ -d /opt/hiclaw/agent/worker-skills ]; then
        cp -rf /opt/hiclaw/agent/worker-skills/* "${WORKSPACE}/worker-skills/" 2>/dev/null || true
    fi

    # Copy worker-agent definitions
    if [ -d /opt/hiclaw/agent/worker-agent ]; then
        cp -rf /opt/hiclaw/agent/worker-agent "${WORKSPACE}/worker-agent"
    fi
    if [ -d /opt/hiclaw/agent/copaw-worker-agent ]; then
        cp -rf /opt/hiclaw/agent/copaw-worker-agent "${WORKSPACE}/copaw-worker-agent"
    fi

    # Pre-create state files to avoid ENOENT on first heartbeat
    for f in state.json workers-registry.json worker-lifecycle.json; do
        if [ ! -f "${WORKSPACE}/${f}" ]; then
            echo '{"active_tasks":[],"updated_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "${WORKSPACE}/${f}"
            log "Created initial ${f}"
        fi
    done

    echo "${IMAGE_VERSION}" > "${WORKSPACE}/.builtin-version"
    touch "${WORKSPACE}/.initialized"
    log "Agent files initialized (version: ${IMAGE_VERSION})"
else
    log "Workspace up to date (version: ${IMAGE_VERSION})"
fi

# Symlink hiclaw-fs into workspace for agent access
ln -sfn "${HICLAW_FS}" "${WORKSPACE}/hiclaw-fs"

# ============================================================
# Step 6: Generate openclaw.json
# ============================================================
log "Generating Manager openclaw.json..."

# Resolve model parameters
MODEL_NAME="${HICLAW_DEFAULT_MODEL}"
case "${MODEL_NAME}" in
    gpt-5.3-codex|gpt-5-mini|gpt-5-nano)
        export MODEL_CONTEXT_WINDOW=400000 MODEL_MAX_TOKENS=128000 ;;
    claude-opus-4-6)
        export MODEL_CONTEXT_WINDOW=1000000 MODEL_MAX_TOKENS=128000 ;;
    claude-sonnet-4-6)
        export MODEL_CONTEXT_WINDOW=1000000 MODEL_MAX_TOKENS=64000 ;;
    claude-haiku-4-5)
        export MODEL_CONTEXT_WINDOW=200000 MODEL_MAX_TOKENS=64000 ;;
    qwen3.5-plus)
        export MODEL_CONTEXT_WINDOW=960000 MODEL_MAX_TOKENS=64000 ;;
    qwen-plus)
        export MODEL_CONTEXT_WINDOW=131072 MODEL_MAX_TOKENS=8192 ;;
    deepseek-chat|deepseek-reasoner|kimi-k2.5)
        export MODEL_CONTEXT_WINDOW=256000 MODEL_MAX_TOKENS=128000 ;;
    *)
        export MODEL_CONTEXT_WINDOW=200000 MODEL_MAX_TOKENS=128000 ;;
esac
export MODEL_REASONING=true

case "${MODEL_NAME}" in
    gpt-5.4|gpt-5.3-codex|gpt-5-mini|gpt-5-nano|claude-opus-4-6|claude-sonnet-4-6|claude-haiku-4-5|qwen3.5-plus|kimi-k2.5)
        export MODEL_INPUT='["text", "image"]' ;;
    *)
        export MODEL_INPUT='["text"]' ;;
esac

log "Model: ${MODEL_NAME} (context=${MODEL_CONTEXT_WINDOW}, maxTokens=${MODEL_MAX_TOKENS})"

if [ -f "${WORKSPACE}/openclaw.json" ]; then
    log "Updating existing openclaw.json with current credentials..."
    jq --arg token "${MANAGER_MATRIX_TOKEN}" \
       --arg key "${HICLAW_MANAGER_GATEWAY_KEY}" \
       --arg model "${MODEL_NAME}" \
       --arg homeserver "${HICLAW_MATRIX_URL}" \
       --arg gateway "${HICLAW_AI_GATEWAY_URL}/v1" \
       --argjson ctx "${MODEL_CONTEXT_WINDOW}" \
       --argjson max "${MODEL_MAX_TOKENS}" \
       --argjson input "${MODEL_INPUT}" \
       '.gateway.bind = "lan"
        | .channels.matrix.homeserver = $homeserver
        | .channels.matrix.accessToken = $token
        | .hooks.token = $key
        | .models.providers["hiclaw-gateway"].baseUrl = $gateway
        | .models.providers["hiclaw-gateway"].apiKey = $key
        | .models.providers["hiclaw-gateway"].models[0].id = $model
        | .models.providers["hiclaw-gateway"].models[0].name = $model
        | .models.providers["hiclaw-gateway"].models[0].contextWindow = $ctx
        | .models.providers["hiclaw-gateway"].models[0].maxTokens = $max
        | .models.providers["hiclaw-gateway"].models[0].input = $input
        | .agents.defaults.model.primary = ("hiclaw-gateway/" + $model)' \
       "${WORKSPACE}/openclaw.json" > /tmp/openclaw.json.tmp && \
        mv /tmp/openclaw.json.tmp "${WORKSPACE}/openclaw.json"
else
    log "Generating openclaw.json from cloud template..."
    envsubst < /opt/hiclaw/cloud-configs/manager-cloud-openclaw.json.tmpl > "${WORKSPACE}/openclaw.json"
fi

# Symlink for OpenClaw discovery
mkdir -p "${HOME}/.openclaw"
ln -sf "${WORKSPACE}/openclaw.json" "${HOME}/.openclaw/openclaw.json"
export OPENCLAW_CONFIG_PATH="${WORKSPACE}/openclaw.json"

# ============================================================
# Step 7: Start background file sync (workspace ↔ OSS)
# ============================================================
log "Starting background file sync..."

# Local → OSS: change-triggered sync
(
    source /opt/hiclaw/scripts/lib/oss-credentials.sh
    while true; do
        CHANGED=$(find "${WORKSPACE}/" -type f -newermt "15 seconds ago" 2>/dev/null | head -1)
        if [ -n "${CHANGED}" ]; then
            ensure_mc_credentials
            mc mirror "${WORKSPACE}/" "hiclaw/${HICLAW_OSS_BUCKET}/manager/" --overwrite \
                --exclude ".openclaw/**" --exclude ".cache/**" --exclude ".npm/**" \
                --exclude ".local/**" --exclude ".mc/**" 2>/dev/null || true
        fi
        sleep 10
    done
) &
log "Local→OSS sync started (PID: $!)"

# OSS → Local: periodic pull (shared data, agent configs)
(
    source /opt/hiclaw/scripts/lib/oss-credentials.sh
    while true; do
        sleep 300
        ensure_mc_credentials
        mc mirror "hiclaw/${HICLAW_OSS_BUCKET}/shared/" "${HICLAW_FS}/shared/" --overwrite --newer-than "5m" 2>/dev/null || true
        mc mirror "hiclaw/${HICLAW_OSS_BUCKET}/agents/" "${HICLAW_FS}/agents/" --overwrite --newer-than "5m" 2>/dev/null || true
    done
) &
log "OSS→Local sync started (every 5m, PID: $!)"

# ============================================================
# Step 8: Sync initial workspace to OSS
# ============================================================
log "Syncing initial workspace to OSS..."
ensure_mc_credentials
mc mirror "${WORKSPACE}/" "hiclaw/${HICLAW_OSS_BUCKET}/manager/" --overwrite \
    --exclude ".openclaw/**" --exclude ".cache/**" 2>/dev/null || true

# ============================================================
# Step 9: Start OpenClaw Manager Agent
# ============================================================
log "=== Network connectivity test ==="
log "AI Gateway URL: ${HICLAW_AI_GATEWAY_URL}"
log "Matrix URL: ${HICLAW_MATRIX_URL}"

# Test AI Gateway
_GW_TEST=$(curl -sf --max-time 5 "${HICLAW_AI_GATEWAY_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${HICLAW_MANAGER_GATEWAY_KEY}" \
    -d '{"model":"'"${HICLAW_DEFAULT_MODEL}"'","messages":[{"role":"user","content":"ping"}],"max_tokens":5}' 2>&1) || true
log "AI Gateway test: ${_GW_TEST:0:200}"

# Test Matrix send capability
_MATRIX_TEST=$(curl -sf --max-time 5 "${HICLAW_MATRIX_URL}/_matrix/client/v3/account/whoami" \
    -H "Authorization: Bearer ${MANAGER_MATRIX_TOKEN}" 2>&1) || true
log "Matrix whoami: ${_MATRIX_TEST:0:200}"

# Print generated openclaw.json gateway config for debugging
log "openclaw.json gateway.bind: $(jq -r '.gateway.bind // "NOT SET"' "${WORKSPACE}/openclaw.json" 2>/dev/null)"
log "openclaw.json baseUrl: $(jq -r '.models.providers["hiclaw-gateway"].baseUrl // "NOT SET"' "${WORKSPACE}/openclaw.json" 2>/dev/null)"

log "Starting Manager Agent (OpenClaw)..."
export HOME="${WORKSPACE}"
cd "${WORKSPACE}"
exec openclaw gateway run --verbose --force --bind lan
