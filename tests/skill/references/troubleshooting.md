# HiClaw 常见问题与解决方案

## 测试 Hang 问题

### 症状：测试超时，没有失败但也没有完成

### 诊断步骤

1. 检查 Manager 是否在等待某个信号：
```bash
docker exec hiclaw-manager grep "Waiting for" /var/log/hiclaw/manager-agent.log | tail -10
```

2. 检查 Worker 发送的消息是否被处理：
```bash
docker exec hiclaw-manager grep -E "PHASE[0-9]_DONE|REVISION_NEEDED" /var/log/hiclaw/manager-agent.log
```

3. 关键：检查 `wasMentioned` 状态：
```bash
docker exec hiclaw-manager grep "resolveMentions (inbound)" /var/log/hiclaw/manager-agent.log | tail -20
```

### 常见原因

#### 1. Worker 没有 @mention Manager（已修复）

**症状**：
```
resolveMentions (inbound): wasMentioned=false text="PHASE2_DONE..."
```

**原因**：Worker 在项目房间发送消息时没有 @mention Manager，导致 Manager 忽略了这条消息。

**解决方案**（已在 v1.0.8+ 修复）：
- Manager 在分配多 phase 任务时自动添加 "Multi-Phase Collaboration Protocol"
- Worker AGENTS.md 增加了独立的 gotcha 说明 phase 完成必须 @mention

#### 2. LLM 响应超时

**症状**：
```
[tools] exec failed: timeout
```

**解决方案**：增加 LLM 超时时间或检查 API 可用性

#### 3. 容器资源不足

**症状**：
```
OOMKilled
```

**解决方案**：增加 Docker 内存限制

## 安装问题

### 容器启动失败

```bash
# 检查容器日志
docker logs hiclaw-manager

# 检查端口占用
netstat -tlnp | grep -E "18080|18088|18001"
```

### 镜像构建失败

```bash
# 清理 Docker 缓存重新构建
docker builder prune
make build
```

## Worker 问题

### Worker 容器无法启动

```bash
# 检查 Worker 镜像
docker images | grep hiclaw

# 手动启动测试
docker run --rm -it hiclaw/worker-agent:latest /bin/bash
```

### Worker 无法连接 Matrix

```bash
# 检查 Worker 的 Matrix 凭证（容器内路径是固定的）
docker exec hiclaw-worker-alice cat /root/.openclaw/channels/matrix/credentials.json
```

## 测试跳过问题

### GitHub 测试被跳过

需要设置 `HICLAW_GITHUB_TOKEN`：
```bash
export HICLAW_GITHUB_TOKEN="ghp_xxx"
make test
```

## 性能优化

### 测试运行太慢

1. 使用 `--skip-build` 跳过镜像构建
2. 使用 `--use-existing` 使用现有安装
3. 使用 `--test-filter` 只运行特定测试

```bash
./tests/run-all-tests.sh --skip-build --use-existing --test-filter "01 02 03"
```

### LLM Token 消耗过高

查看 metrics 文件了解各测试的 token 消耗：
```bash
# 在仓库目录下
cat tests/output/metrics-*.json | jq '.totals.tokens'
```

## 快速诊断命令

```bash
# 一键导出所有日志（需要先运行 hiclaw-debug.sh 脚本）
hiclaw-debug.sh all

# 仅分析 hang 问题
hiclaw-debug.sh analyze

# 查看 Manager 容器状态
docker ps --filter "name=hiclaw"

# 快速查看最近的错误
docker exec hiclaw-manager tail -50 /var/log/hiclaw/manager-agent-error.log
```
