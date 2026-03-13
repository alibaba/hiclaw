#!/bin/sh
# cloud-element entrypoint: inject config.json from environment variable, then start nginx.
#
# Environment variables:
#   ELEMENT_CONFIG_JSON  — full config.json content (JSON string)
#   MATRIX_SERVER_URL    — homeserver base_url (fallback if ELEMENT_CONFIG_JSON not set)

set -e

CONFIG_PATH="/app/config.json"

if [ -n "$ELEMENT_CONFIG_JSON" ]; then
    echo "$ELEMENT_CONFIG_JSON" > "$CONFIG_PATH"
    echo "[entrypoint] Wrote config.json from ELEMENT_CONFIG_JSON"
elif [ -n "$MATRIX_SERVER_URL" ]; then
    cat > "$CONFIG_PATH" <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "${MATRIX_SERVER_URL}"
        }
    },
    "brand": "${ELEMENT_BRAND:-HiClaw}",
    "disable_guests": true,
    "disable_custom_urls": false
}
EOF
    echo "[entrypoint] Wrote config.json with base_url=${MATRIX_SERVER_URL}"
else
    echo "[entrypoint] WARNING: No ELEMENT_CONFIG_JSON or MATRIX_SERVER_URL set, using default config"
fi

# Delegate to the original nginx entrypoint
exec /docker-entrypoint.sh "$@"
