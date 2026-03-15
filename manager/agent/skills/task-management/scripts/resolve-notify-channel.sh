#!/bin/bash
# resolve-notify-channel.sh - Resolve the admin notification channel
#
# Reads primary-channel.json and state.json to determine where to send
# admin notifications. Outputs JSON with channel info for the Agent to
# use with the `message` tool.
#
# Usage:
#   resolve-notify-channel.sh
#
# Output (JSON):
#   { "channel": "dingtalk", "target": "...", "via": "primary-channel" }
#   { "channel": "matrix",  "target": "room:!abc:domain", "via": "admin-dm" }
#   { "channel": "none",    "target": null, "via": "none", "error": "..." }

set -euo pipefail

PRIMARY_CHANNEL_FILE="${HOME}/primary-channel.json"
STATE_FILE="${HOME}/state.json"

# Try primary channel first
if [ -f "$PRIMARY_CHANNEL_FILE" ]; then
    confirmed=$(jq -r '.confirmed // false' "$PRIMARY_CHANNEL_FILE")
    channel=$(jq -r '.channel // "matrix"' "$PRIMARY_CHANNEL_FILE")

    if [ "$confirmed" = "true" ] && [ "$channel" != "matrix" ]; then
        target=$(jq -r '.to // empty' "$PRIMARY_CHANNEL_FILE")
        if [ -n "$target" ]; then
            jq -n --arg ch "$channel" --arg tgt "$target" \
                '{"channel": $ch, "target": $tgt, "via": "primary-channel"}'
            exit 0
        fi
    fi
fi

# Fallback: Matrix DM from state.json
if [ -f "$STATE_FILE" ]; then
    admin_dm=$(jq -r '.admin_dm_room_id // empty' "$STATE_FILE")
    if [ -n "$admin_dm" ] && [ "$admin_dm" != "null" ]; then
        jq -n --arg room "$admin_dm" \
            '{"channel": "matrix", "target": ("room:" + $room), "via": "admin-dm"}'
        exit 0
    fi
fi

# No channel available
jq -n '{"channel": "none", "target": null, "via": "none", "error": "No primary channel configured and admin_dm_room_id not set in state.json. Run HEARTBEAT Step 1 to discover admin DM room."}'
exit 0
