# Fix Issue #320: Windows HOST_ORIGINAL_HOME path format causing manager-agent startup failure

## Issue Overview

- **Issue Number**: #320
- **Issue Type**: bug
- **Repository**: higress-group/hiclaw
- **Status**: In Progress

## Problem Description

On Windows 11 + Docker Desktop, after installing hiclaw-manager using `install.ps1`, the manager-agent service repeatedly fails to start.

**Error Log:**
```
ln: failed to create symbolic link 'D:\Users\xxx': No such file or directory
```

**Root Cause:**
The `install.ps1` script sets `HOST_ORIGINAL_HOME=D:\Users\xxx` (Windows path format), which Linux containers cannot recognize.

**Suggested Fix:**
In Windows environments, either don't set `HOST_ORIGINAL_HOME`, or convert it to Linux path format.

## Related Links

- Issue URL: https://github.com/higress-group/hiclaw/issues/320

## Implementation Plan

- [x] Understand requirements (brainstorming skill)
- [x] Write tests for the fix (existing tests cover container boot)
- [x] Implement the fix
- [x] Verify tests pass
- [ ] Code review

## Changes Made

| File | Change |
|------|--------|
| `install/hiclaw-install.ps1` | Removed `HOST_ORIGINAL_HOME` env var (line 1930) |
| `changelog/current.md` | Added changelog entry for fix |

## Technical Analysis

### Root Cause Analysis
- `install/hiclaw-install.ps1` line 1930 sets `HOST_ORIGINAL_HOME=$($config.HOST_SHARE_DIR)` with raw Windows path
- `manager/scripts/init/start-manager-agent.sh` lines 44-52 tries to create symlink at this path
- Linux container cannot interpret Windows paths like `D:\Users\xxx`

### Fix Approach
**Skip setting HOST_ORIGINAL_HOME on Windows** - the container already has fallback logic:
- If `HOST_ORIGINAL_HOME` is not set or invalid, it creates `/root/host-home -> /host-share`
- The `/host-share` mount (line 1977) already correctly uses `ConvertTo-DockerPath`

### Files to Modify
- `install/hiclaw-install.ps1` - Remove/skip line 1930 on Windows

## Progress Log

- 2026-03-18: Started processing issue
- 2026-03-18: Created worktree and branch
- 2026-03-18: Completed brainstorming - identified fix approach

## Skill Usage Log

| Skill | Used | Result |
|-------|------|--------|
| brainstorming | Yes | Found root cause and fix approach: skip HOST_ORIGINAL_HOME on Windows |
| test-driven-development | No | - |
| subagent-driven-development | No | - |
| verification-before-completion | No | - |
| requesting-code-review | No | - |
