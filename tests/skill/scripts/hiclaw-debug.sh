#!/bin/bash
# hiclaw-debug.sh - 导出 HiClaw debug 日志的辅助脚本
# 用法: hiclaw-debug.sh [command] [output_dir] [test_output_dir]
#
# Commands:
#   manager     - 导出 Manager 日志
#   worker      - 导出所有 Worker 日志
#   test        - 导出测试输出
#   all         - 导出所有日志 (默认)
#   analyze     - 分析 hang 住问题
#
# Arguments:
#   output_dir      - 日志输出目录 (默认: ./hiclaw-debug-YYYYMMDD-HHMMSS)
#   test_output_dir - 测试输出目录 (默认: 自动检测或从环境变量读取)

set -e

COMMAND="${1:-all}"
OUTPUT_DIR="${2:-./hiclaw-debug-$(date +%Y%m%d-%H%M%S)}"
TEST_OUTPUT_DIR="${3:-${HICLAW_TEST_OUTPUT_DIR:-}}"

MANAGER_CONTAINER="${HICLAW_MANAGER_CONTAINER:-hiclaw-manager}"

echo "=== HiClaw Debug Log Exporter ==="
echo "Output directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

export_manager_logs() {
    echo "[1/4] Exporting Manager logs..."
    
    # Manager 容器日志
    docker logs "$MANAGER_CONTAINER" > "$OUTPUT_DIR/manager-container.log" 2>&1 || true
    
    # Manager Agent 日志
    docker exec "$MANAGER_CONTAINER" cat /var/log/hiclaw/manager-agent.log \
        > "$OUTPUT_DIR/manager-agent.log" 2>/dev/null || true
    
    # Manager Agent 错误日志
    docker exec "$MANAGER_CONTAINER" cat /var/log/hiclaw/manager-agent-error.log \
        > "$OUTPUT_DIR/manager-agent-error.log" 2>/dev/null || true
    
    # 其他组件日志
    for component in higress-gateway higress-controller tuwunel minio; do
        docker exec "$MANAGER_CONTAINER" cat "/var/log/hiclaw/${component}.log" \
            > "$OUTPUT_DIR/${component}.log" 2>/dev/null || true
    done
    
    echo "  Manager logs exported"
}

export_worker_logs() {
    echo "[2/4] Exporting Worker logs..."
    
    WORKERS=$(docker ps --filter "name=hiclaw-worker" --format "{{.Names}}")
    
    if [ -z "$WORKERS" ]; then
        echo "  No worker containers found"
        return
    fi
    
    for worker in $WORKERS; do
        echo "  Exporting $worker..."
        
        # 容器日志
        docker logs "$worker" > "$OUTPUT_DIR/${worker}.log" 2>&1 || true
        
        # Agent 日志（如果存在）
        docker exec "$worker" cat /var/log/hiclaw/openclaw-gateway.log \
            > "$OUTPUT_DIR/${worker}-gateway.log" 2>/dev/null || true
    done
    
    echo "  Worker logs exported"
}

export_test_output() {
    echo "[3/4] Exporting test output..."
    
    # 自动检测测试输出目录
    if [ -z "$TEST_OUTPUT_DIR" ]; then
        for dir in "./tests/output" "../tests/output" "/tmp/hiclaw/tests/output"; do
            if [ -d "$dir" ]; then
                TEST_OUTPUT_DIR="$dir"
                break
            fi
        done
    fi
    
    if [ -n "$TEST_OUTPUT_DIR" ] && [ -d "$TEST_OUTPUT_DIR" ]; then
        cp -r "$TEST_OUTPUT_DIR" "$OUTPUT_DIR/tests-output"
        echo "  Test output exported from: $TEST_OUTPUT_DIR"
    else
        echo "  No test output found (set HICLAW_TEST_OUTPUT_DIR or pass as argument)"
    fi
}

analyze_hang() {
    echo "[4/4] Analyzing potential hang issues..."
    
    ANALYSIS_FILE="$OUTPUT_DIR/hang-analysis.txt"
    
    {
        echo "=== HiClaw Hang Analysis ==="
        echo "Generated: $(date)"
        echo ""
        
        echo "=== Recent PHASE signals ==="
        docker exec "$MANAGER_CONTAINER" grep -E "PHASE[0-9]_DONE|REVISION_NEEDED" \
            /var/log/hiclaw/manager-agent.log 2>/dev/null | tail -20 || echo "No phase signals found"
        echo ""
        
        echo "=== Mentions Analysis (last 30) ==="
        docker exec "$MANAGER_CONTAINER" grep "resolveMentions (inbound)" \
            /var/log/hiclaw/manager-agent.log 2>/dev/null | tail -30 || echo "No mention analysis found"
        echo ""
        
        echo "=== Waiting Messages ==="
        docker exec "$MANAGER_CONTAINER" grep -E "Waiting for.*report.*DONE" \
            /var/log/hiclaw/manager-agent.log 2>/dev/null | tail -10 || echo "No waiting messages found"
        echo ""
        
        echo "=== Worker Status ==="
        docker ps --filter "name=hiclaw-worker" --format "table {{.Names}}\t{{.Status}}"
        
    } > "$ANALYSIS_FILE" 2>&1
    
    echo "  Analysis saved to $ANALYSIS_FILE"
    
    # 打印关键发现
    echo ""
    echo "=== Key Findings ==="
    
    # 检查是否有未 @mention 的消息
    UNMENTIONED=$(docker exec "$MANAGER_CONTAINER" grep "wasMentioned=false" \
        /var/log/hiclaw/manager-agent.log 2>/dev/null | grep "PHASE\|DONE\|REVISION" | tail -5 || true)
    
    if [ -n "$UNMENTIONED" ]; then
        echo "⚠️  Found messages NOT @mentioned (may cause hang):"
        echo "$UNMENTIONED"
    else
        echo "✓ No obvious mention issues found"
    fi
}

case "$COMMAND" in
    manager)
        export_manager_logs
        ;;
    worker)
        export_worker_logs
        ;;
    test)
        export_test_output
        ;;
    analyze)
        analyze_hang
        ;;
    all)
        export_manager_logs
        export_worker_logs
        export_test_output
        analyze_hang
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Usage: $0 [manager|worker|test|analyze|all]"
        exit 1
        ;;
esac

echo ""
echo "=== Export Complete ==="
echo "Logs saved to: $OUTPUT_DIR"
echo ""
echo "To analyze:"
echo "  cat $OUTPUT_DIR/hang-analysis.txt"
echo "  grep 'wasMentioned' $OUTPUT_DIR/manager-agent.log"
