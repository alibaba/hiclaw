#!/bin/bash
# resolve-dag.sh - DAG dependency resolver for team project plan.md
#
# Parses plan.md task lines and resolves dependencies to determine
# which tasks are ready to execute, blocked, in-progress, or completed.
#
# Usage:
#   resolve-dag.sh --plan <PATH_TO_PLAN.md> --action ready|status|validate
#
# Actions:
#   ready    - Output tasks whose dependencies are all satisfied (pending + unblocked)
#   status   - Output full DAG state (all tasks grouped by status)
#   validate - Check for cycles in the dependency graph
#
# Task line format in plan.md:
#   - [ ] st-01 — Task title (assigned: @worker:domain)
#   - [ ] st-02 — Task title (assigned: @worker:domain, depends: st-01, st-03)
#
# Status markers: [ ] pending, [~] in-progress, [x] completed, [!] blocked, [→] revision

set -euo pipefail

PLAN_FILE=""
ACTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan)   PLAN_FILE="$2"; shift 2 ;;
        --action) ACTION="$2";    shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [ -z "${PLAN_FILE}" ] || [ -z "${ACTION}" ]; then
    echo "Usage: resolve-dag.sh --plan <PATH> --action <ready|status|validate>" >&2
    exit 1
fi

if [ ! -f "${PLAN_FILE}" ]; then
    echo "ERROR: Plan file not found: ${PLAN_FILE}" >&2
    exit 1
fi

# ─── Parse task lines from plan.md ────────────────────────────────────────────
# Expected format:
#   - [ ] st-01 — Title text (assigned: @worker:domain)
#   - [x] st-02 — Title text (assigned: @worker:domain, depends: st-01)
# We extract: status_marker, task_id, title, assigned_worker, depends_list

parse_tasks() {
    # Match lines starting with "- [" followed by a status marker
    grep -E '^\s*- \[[ x~!→]\] ' "${PLAN_FILE}" | while IFS= read -r line; do
        # Extract status marker
        local marker
        marker=$(echo "$line" | sed -n 's/.*- \[\(.\)\].*/\1/p')

        # Map marker to status
        local status
        case "$marker" in
            ' ') status="pending" ;;
            '~') status="in_progress" ;;
            'x') status="completed" ;;
            '!') status="blocked" ;;
            '→') status="revision" ;;
            *)   status="unknown" ;;
        esac

        # Extract task ID (first word after the marker)
        local task_id
        task_id=$(echo "$line" | sed -n 's/.*- \[.\] \([a-zA-Z0-9_-]*\).*/\1/p')

        # Extract title (between task_id and the parenthetical)
        local title
        title=$(echo "$line" | sed -n 's/.*- \[.\] [a-zA-Z0-9_-]* — \(.*\) (assigned:.*/\1/p')
        [ -z "$title" ] && title=$(echo "$line" | sed -n 's/.*- \[.\] [a-zA-Z0-9_-]* — \(.*\)/\1/p')

        # Extract assigned worker (from "assigned: @worker:domain")
        local assigned
        assigned=$(echo "$line" | sed -n 's/.*assigned: @\([^:)]*\).*/\1/p')

        # Extract depends list (from "depends: st-01, st-02")
        local depends
        depends=$(echo "$line" | sed -n 's/.*depends: \([^)]*\).*/\1/p')

        # Output as JSON
        local depends_json="[]"
        if [ -n "$depends" ]; then
            depends_json=$(echo "$depends" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)
        fi

        jq -n \
            --arg id "$task_id" \
            --arg title "$title" \
            --arg status "$status" \
            --arg assigned "$assigned" \
            --argjson depends "$depends_json" \
            '{id: $id, title: $title, status: $status, assigned: $assigned, depends: $depends}'
    done | jq -s '.'
}

# ─── Action: ready ────────────────────────────────────────────────────────────
# Find pending tasks whose dependencies are all completed

action_ready() {
    local tasks
    tasks=$(parse_tasks)

    # Get list of completed task IDs
    local completed_ids
    completed_ids=$(echo "$tasks" | jq -r '[.[] | select(.status == "completed") | .id]')

    # Find ready tasks: pending + all depends are in completed_ids
    local ready
    ready=$(echo "$tasks" | jq --argjson done "$completed_ids" '
        [.[] | select(.status == "pending") |
            select(.depends | length == 0 or (. as $deps | [$deps[] | select(. as $d | $done | index($d) | not)] | length == 0))]')

    # Find blocked tasks: pending + some depends not completed
    local blocked
    blocked=$(echo "$tasks" | jq --argjson done "$completed_ids" '
        [.[] | select(.status == "pending") |
            select(.depends | length > 0 and (. as $deps | [$deps[] | select(. as $d | $done | index($d) | not)] | length > 0)) |
            {id, blocked_by: [.depends[] | select(. as $d | $done | index($d) | not)]}]')

    # In-progress and completed
    local in_progress
    in_progress=$(echo "$tasks" | jq '[.[] | select(.status == "in_progress") | {id, title, assigned}]')
    local completed
    completed=$(echo "$tasks" | jq '[.[] | select(.status == "completed") | {id, title, assigned}]')

    jq -n \
        --argjson ready "$ready" \
        --argjson blocked "$blocked" \
        --argjson in_progress "$in_progress" \
        --argjson completed "$completed" \
        '{ready_tasks: $ready, blocked_tasks: $blocked, in_progress: $in_progress, completed: $completed}'
}

# ─── Action: status ───────────────────────────────────────────────────────────
# Full DAG status grouped by state

action_status() {
    local tasks
    tasks=$(parse_tasks)

    echo "$tasks" | jq '{
        pending:     [.[] | select(.status == "pending")],
        in_progress: [.[] | select(.status == "in_progress")],
        completed:   [.[] | select(.status == "completed")],
        blocked:     [.[] | select(.status == "blocked")],
        revision:    [.[] | select(.status == "revision")],
        total:       length
    }'
}

# ─── Action: validate ─────────────────────────────────────────────────────────
# Check for cycles using iterative topological sort (Kahn's algorithm)

action_validate() {
    local tasks
    tasks=$(parse_tasks)

    local total
    total=$(echo "$tasks" | jq 'length')

    if [ "$total" -eq 0 ]; then
        echo '{"valid": true, "message": "No tasks found in plan.md", "task_count": 0}'
        return 0
    fi

    # Kahn's algorithm: iteratively remove nodes with no incoming edges
    local result
    result=$(echo "$tasks" | jq '
        # Build adjacency: for each task, track its unresolved dependency count
        . as $tasks |
        [.[] | .id] as $all_ids |

        # Validate: check all depends reference existing task IDs
        (reduce .[] as $t ([]; . + [$t.depends[] | select(. as $d | $all_ids | index($d) | not)])) as $missing |
        if ($missing | length) > 0 then
            {valid: false, message: "Unknown task IDs in depends: \($missing | unique | join(", "))", task_count: ($tasks | length)}
        else
            # Kahn: compute in-degree for each node
            (reduce $tasks[] as $t (
                {};
                . as $deg |
                ($t.id) as $id |
                (if $deg[$id] then $deg else $deg + {($id): 0} end) as $deg |
                reduce ($t.depends[]) as $dep (
                    $deg;
                    . + {($id): ((.[$id] // 0) + 1)}
                )
            )) as $in_degree |

            # Find initial zero-degree nodes
            [$all_ids[] | select(($in_degree[.] // 0) == 0)] as $queue |

            # Process queue
            {queue: $queue, visited: 0, in_degree: $in_degree} |
            until(.queue | length == 0;
                .queue[0] as $node |
                .queue[1:] as $rest |
                .visited + 1 as $v |
                # Find tasks that depend on $node and decrement their in-degree
                (reduce ($tasks[] | select(.depends | index($node))) as $t (
                    {deg: .in_degree, new_ready: []};
                    ($t.id) as $tid |
                    ((.deg[$tid] // 0) - 1) as $new_deg |
                    .deg + {($tid): $new_deg} |
                    if $new_deg == 0 then .new_ready += [$tid] else . end
                )) as $update |
                {queue: ($rest + $update.new_ready), visited: $v, in_degree: $update.deg}
            ) |
            if .visited == ($tasks | length) then
                {valid: true, message: "DAG is valid — no cycles detected", task_count: ($tasks | length)}
            else
                {valid: false, message: "Cycle detected in DAG! \(.visited) of \($tasks | length) tasks are reachable", task_count: ($tasks | length)}
            end
        end
    ')

    echo "$result"

    # Exit with error code if invalid
    local valid
    valid=$(echo "$result" | jq -r '.valid')
    if [ "$valid" != "true" ]; then
        return 1
    fi
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────

case "$ACTION" in
    ready)    action_ready ;;
    status)   action_status ;;
    validate) action_validate ;;
    *)
        echo "ERROR: Unknown action '$ACTION'. Use: ready, status, validate" >&2
        exit 1
        ;;
esac
