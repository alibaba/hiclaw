#!/bin/bash
# Detect available AI coding CLI tools and their config directories
# Output: JSON with available tools and details
# Usage: bash detect-available-cli.sh

result='{"available":[],"details":{}}'

for cli in claude gemini qodercli; do
    binary_ok=false
    config_ok=false

    if command -v "$cli" &>/dev/null; then
        binary_ok=true
    fi

    case "$cli" in
        claude)   [ -d "$HOME/.claude" ]  && config_ok=true ;;
        gemini)   [ -d "$HOME/.gemini" ]  && config_ok=true ;;
        qodercli) [ -d "$HOME/.qoder" ]   && config_ok=true ;;
    esac

    if $binary_ok && $config_ok; then
        result=$(echo "$result" | jq --arg c "$cli" '.available += [$c]')
    fi

    result=$(echo "$result" | jq \
        --arg c "$cli" \
        --argjson b "$binary_ok" \
        --argjson co "$config_ok" \
        '.details[$c] = {binary: $b, config: $co}')
done

echo "$result"
