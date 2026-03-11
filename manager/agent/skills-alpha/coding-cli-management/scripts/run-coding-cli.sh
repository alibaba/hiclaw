#!/bin/bash
# Execute an AI coding CLI tool in a given workspace
# Usage: run-coding-cli.sh --cli <tool> --workspace <dir> --prompt-file <file> [--timeout <secs>]

set -e

cli=""
workspace=""
prompt_file=""
timeout_secs=600

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli)         cli="$2";         shift 2 ;;
        --workspace)   workspace="$2";   shift 2 ;;
        --prompt-file) prompt_file="$2"; shift 2 ;;
        --timeout)     timeout_secs="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$cli" ] || [ -z "$workspace" ] || [ -z "$prompt_file" ]; then
    echo "Usage: $0 --cli <tool> --workspace <dir> --prompt-file <file> [--timeout <secs>]" >&2
    exit 1
fi

if [ ! -f "$prompt_file" ]; then
    echo "Prompt file not found: $prompt_file" >&2
    exit 1
fi

if [ ! -d "$workspace" ]; then
    echo "Workspace directory not found: $workspace" >&2
    exit 1
fi

# Save output to log file in the workspace's coding-cli-logs directory
log_dir="$workspace/coding-cli-logs"
mkdir -p "$log_dir"
timestamp=$(date +%Y%m%d-%H%M%S)
log_file="$log_dir/run-${timestamp}.log"

echo "[run-coding-cli] cli=$cli workspace=$workspace prompt_file=$prompt_file timeout=${timeout_secs}s"
echo "[run-coding-cli] Log: $log_file"

cd "$workspace"

case "$cli" in
    claude)
        timeout "$timeout_secs" claude -p "$(cat "$prompt_file")" \
            --dangerously-skip-permissions --output-format text 2>&1 | tee "$log_file"
        exit_code=${PIPESTATUS[0]}
        ;;
    gemini)
        timeout "$timeout_secs" gemini -p "$(cat "$prompt_file")" -y 2>&1 | tee "$log_file"
        exit_code=${PIPESTATUS[0]}
        ;;
    qodercli)
        timeout "$timeout_secs" qodercli -p "$(cat "$prompt_file")" \
            --yolo -w "$workspace" 2>&1 | tee "$log_file"
        exit_code=${PIPESTATUS[0]}
        ;;
    *)
        echo "Unknown CLI tool: $cli. Supported: claude, gemini, qodercli" >&2 | tee -a "$log_file"
        exit 1
        ;;
esac

if [ "$exit_code" -eq 124 ]; then
    echo "[run-coding-cli] TIMEOUT after ${timeout_secs}s" | tee -a "$log_file"
    exit 124
fi

echo "[run-coding-cli] Finished with exit code $exit_code" | tee -a "$log_file"
exit "$exit_code"
