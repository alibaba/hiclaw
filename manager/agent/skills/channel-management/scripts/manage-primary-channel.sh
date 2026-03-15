#!/bin/bash
# manage-primary-channel.sh - Atomic primary-channel.json operations
#
# Replaces manual cat/jq writes by the Agent with validated, atomic script calls.
#
# Usage:
#   manage-primary-channel.sh --action confirm --channel CH --to TO --sender-id SID [--channel-name NAME]
#   manage-primary-channel.sh --action reset
#   manage-primary-channel.sh --action show
#
# Actions:
#   confirm      Set primary channel with validation (requires --channel, --to, --sender-id)
#   reset        Reset to unconfirmed state (Matrix DM fallback)
#   show         Print current primary-channel.json (or default if missing)

set -euo pipefail

PRIMARY_CHANNEL_FILE="${HOME}/primary-channel.json"

_ts() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

action_confirm() {
    # Validate required fields are non-empty
    if [ -z "$CHANNEL" ]; then
        echo "ERROR: --channel is required and cannot be empty" >&2
        exit 1
    fi
    if [ "$CHANNEL" = "matrix" ]; then
        echo "ERROR: primary channel cannot be 'matrix' — Matrix DM is the default fallback. Use --action reset to revert to Matrix DM." >&2
        exit 1
    fi
    if [ -z "$TO" ]; then
        echo "ERROR: --to is required and cannot be empty" >&2
        exit 1
    fi
    if [ -z "$SENDER_ID" ]; then
        echo "ERROR: --sender-id is required and cannot be empty" >&2
        exit 1
    fi

    # Default channel_name to capitalized channel if not provided
    local name="${CHANNEL_NAME:-$(echo "$CHANNEL" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')}"

    local tmp
    tmp=$(mktemp)
    jq -n \
        --argjson confirmed true \
        --arg channel "$CHANNEL" \
        --arg to "$TO" \
        --arg sender_id "$SENDER_ID" \
        --arg channel_name "$name" \
        --arg confirmed_at "$(_ts)" \
        '{
            confirmed: $confirmed,
            channel: $channel,
            to: $to,
            sender_id: $sender_id,
            channel_name: $channel_name,
            confirmed_at: $confirmed_at
        }' > "$tmp" && mv "$tmp" "$PRIMARY_CHANNEL_FILE"

    echo "OK: primary channel set to $name ($CHANNEL), target=$TO"
}

action_reset() {
    local tmp
    tmp=$(mktemp)
    jq -n --argjson confirmed false '{confirmed: $confirmed}' > "$tmp" && mv "$tmp" "$PRIMARY_CHANNEL_FILE"

    echo "OK: primary channel reset to unconfirmed (Matrix DM fallback)"
}

action_show() {
    if [ -f "$PRIMARY_CHANNEL_FILE" ]; then
        cat "$PRIMARY_CHANNEL_FILE"
    else
        echo '{"confirmed":false}'
    fi
}

# ─── Argument parsing ─────────────────────────────────────────────────────────

ACTION=""
CHANNEL=""
TO=""
SENDER_ID=""
CHANNEL_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action)       ACTION="$2";        shift 2 ;;
        --channel)      CHANNEL="$2";       shift 2 ;;
        --to)           TO="$2";            shift 2 ;;
        --sender-id)    SENDER_ID="$2";     shift 2 ;;
        --channel-name) CHANNEL_NAME="$2";  shift 2 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$ACTION" ]; then
    echo "Usage: $0 --action <confirm|reset|show> [options]" >&2
    echo "" >&2
    echo "Actions:" >&2
    echo "  confirm  --channel CH --to TO --sender-id SID [--channel-name NAME]" >&2
    echo "  reset    Reset to unconfirmed (Matrix DM fallback)" >&2
    echo "  show     Print current state" >&2
    exit 1
fi

case "$ACTION" in
    confirm)  action_confirm ;;
    reset)    action_reset ;;
    show)     action_show ;;
    *)
        echo "ERROR: Unknown action '$ACTION'. Use: confirm, reset, show" >&2
        exit 1
        ;;
esac
