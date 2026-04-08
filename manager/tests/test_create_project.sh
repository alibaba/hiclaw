#!/bin/bash
# test_create_project.sh
# create-project.sh 的单元测试：验证项目房间会让 worker 真正入房，并做成员验收。

set -uo pipefail

PASS=0
FAIL=0
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "${TMPDIR_ROOT}"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOURCE_SCRIPT="${PROJECT_ROOT}/manager/agent/skills/project-management/scripts/create-project.sh"
ENV_SCRIPT="${PROJECT_ROOT}/shared/lib/hiclaw-env.sh"

# 统一的断言输出，便于和现有 shell 单测风格保持一致。
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "       expected: $2"; echo "       got:      $3"; FAIL=$((FAIL + 1)); }

# 用于比较精确值。
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "${expected}" = "${actual}" ]; then
        pass "${desc}"
    else
        fail "${desc}" "${expected}" "${actual}"
    fi
}

# 用于断言输出里包含某段文本。
assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "${haystack}" | grep -qF -- "${needle}"; then
        pass "${desc}"
    else
        fail "${desc}" "contains '${needle}'" "not found"
    fi
}

# 每个用例都生成一份可执行副本，避免改动生产脚本只为了测试。
make_test_script() {
    local workdir="$1"
    local fs_root="${workdir}/hiclaw-fs"
    local data_root="${workdir}/data"
    local script_copy="${workdir}/create-project-under-test.sh"
    local env_copy="${workdir}/hiclaw-env-under-test.sh"

    mkdir -p "${fs_root}" "${data_root}/worker-creds"
    sed \
        -e 's|^source /opt/hiclaw/scripts/lib/base.sh.*$|true|' \
        -e 's|^source /opt/hiclaw/scripts/lib/oss-credentials.sh.*$|ensure_mc_credentials() { :; }|' \
        "${ENV_SCRIPT}" > "${env_copy}"
    {
        printf '%s\n' '#!/bin/bash'
        printf '%s\n' '# 测试环境里没有 base.sh，这里补一个静默 log，避免脚本因为日志函数缺失提前退出。'
        printf '%s\n' 'log() { :; }'
        sed -e '1d' \
        -e "s|source /opt/hiclaw/scripts/lib/hiclaw-env.sh|source \"${env_copy}\"|" \
        -e "s|/root/hiclaw-fs|${fs_root}|g" \
        -e "s|/data/worker-creds|${data_root}/worker-creds|g" \
        -e "s|/data/hiclaw-secrets.env|${data_root}/hiclaw-secrets.env|g" \
        "${SOURCE_SCRIPT}"
    } > "${script_copy}"
    chmod +x "${script_copy}"
    printf '%s\n' "${script_copy}"
}

# 生成 curl mock，统一模拟 Matrix login/createRoom/join/joined_members。
create_mock_curl() {
    local mockbin="$1"
    mkdir -p "${mockbin}"
    cat > "${mockbin}/curl" <<'EOF'
#!/bin/sh
set -eu

log_file="${TEST_CURL_LOG:?}"
printf '%s\n' "$*" >> "${log_file}"

body=""
url=""

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--data|--data-raw)
            body="$2"
            shift 2
            ;;
        http://*|https://*)
            url="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

case "${url}" in
    */login)
        case "${body}" in
            *'"user"'*'"manager"'*)
                printf '{"access_token":"manager-token"}'
                ;;
            *'"user"'*'"admin"'*)
                printf '{"access_token":"admin-token"}'
                ;;
            *'"user"'*'"alice"'*)
                printf '{"access_token":"alice-token"}'
                ;;
            *'"user"'*'"bob"'*)
                printf '{"access_token":"bob-token"}'
                ;;
            *)
                printf '{"error":"unknown login"}'
                exit 1
                ;;
        esac
        ;;
    */createRoom)
        printf '{"room_id":"!project:test"}'
        ;;
    */invite)
        printf '{}'
        ;;
    */join)
        printf '{}'
        ;;
    */joined_members*)
        cat "${TEST_JOINED_MEMBERS_FILE:?}"
        ;;
    *)
        printf '{"error":"unexpected url"}'
        exit 1
        ;;
esac
EOF
    chmod +x "${mockbin}/curl"
}

# 生成 mc mock，保证脚本里的 mirror/stat/cp/cat 都能在本地假数据上运行。
create_mock_mc() {
    local mockbin="$1"
    mkdir -p "${mockbin}"
    cat > "${mockbin}/mc" <<'EOF'
#!/bin/sh
set -eu

command_name="${1:-}"
shift || true

resolve_path() {
    local path="$1"
    case "${path}" in
        hiclaw/*)
            printf '%s/%s\n' "${TEST_FAKE_MINIO_ROOT:?}" "${path}"
            ;;
        *)
            printf '%s\n' "${path}"
            ;;
    esac
}

case "${command_name}" in
    mirror)
        src="$(resolve_path "$1")"
        dst="$(resolve_path "$2")"
        mkdir -p "${dst}"
        cp -R "${src}/." "${dst}/"
        ;;
    stat)
        target="$(resolve_path "$1")"
        [ -e "${target}" ]
        ;;
    cp)
        src="$(resolve_path "$1")"
        dst="$(resolve_path "$2")"
        mkdir -p "$(dirname "${dst}")"
        cp "${src}" "${dst}"
        ;;
    cat)
        target="$(resolve_path "$1")"
        cat "${target}"
        ;;
    *)
        echo "unsupported mc command: ${command_name}" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "${mockbin}/mc"
}

# 准备 worker 凭据，让脚本未来可以直接用本地 worker-creds 做 join。
seed_worker_creds() {
    local workdir="$1"
    mkdir -p "${workdir}/data/worker-creds"
    cat > "${workdir}/data/worker-creds/alice.env" <<'EOF'
WORKER_PASSWORD="alice-pass"
EOF
    cat > "${workdir}/data/worker-creds/bob.env" <<'EOF'
WORKER_PASSWORD="bob-pass"
EOF
}

# 准备 fake MinIO 目录，保证脚本里 mirror/stat/cp 可以工作。
seed_fake_minio() {
    local workdir="$1"
    local fake_minio="${workdir}/fake-minio"
    mkdir -p "${fake_minio}/hiclaw/hiclaw-storage/agents/manager"
    mkdir -p "${fake_minio}/hiclaw/hiclaw-storage/shared/projects"
    cat > "${fake_minio}/hiclaw/hiclaw-storage/agents/manager/openclaw.json" <<'EOF'
{
  "channels": {
    "matrix": {
      "groupAllowFrom": []
    }
  }
}
EOF
}

# 运行脚本并返回 stdout/stderr；调用方通过退出码判断成功或失败。
run_create_project() {
    local workdir="$1"
    local joined_members_file="$2"
    local curl_log="$3"
    local script_copy
    local mockbin="${workdir}/mockbin"

    script_copy="$(make_test_script "${workdir}")"
    create_mock_curl "${mockbin}"
    create_mock_mc "${mockbin}"
    seed_worker_creds "${workdir}"
    seed_fake_minio "${workdir}"
    mkdir -p "${workdir}/home"

    PATH="${mockbin}:${PATH}" \
    HOME="${workdir}/home" \
    TEST_CURL_LOG="${curl_log}" \
    TEST_JOINED_MEMBERS_FILE="${joined_members_file}" \
    TEST_FAKE_MINIO_ROOT="${workdir}/fake-minio" \
    HICLAW_MATRIX_SERVER="http://matrix.test" \
    HICLAW_MATRIX_DOMAIN="matrix.test" \
    HICLAW_ADMIN_USER="admin" \
    HICLAW_ADMIN_PASSWORD="admin-pass" \
    MANAGER_MATRIX_TOKEN="manager-token" \
    "${script_copy}" --id "proj-test" --title "Test Project" --workers "alice,bob"
}

echo ""
echo "=== CP1: workers 必须实际 join 项目房间并通过成员验收 ==="
{
    workdir="$(mktemp -d "${TMPDIR_ROOT}/cp1-XXXXXX")"
    joined_members_file="${workdir}/joined-members.json"
    curl_log="${workdir}/curl.log"
    cat > "${joined_members_file}" <<'EOF'
{"joined":{"@manager:matrix.test":{},"@admin:matrix.test":{},"@alice:matrix.test":{},"@bob:matrix.test":{}}}
EOF

    if output="$(run_create_project "${workdir}" "${joined_members_file}" "${curl_log}" 2>&1)"; then
        assert_contains "创建成功输出项目房间" '"!project:test"' "${output}"
        assert_contains "alice 执行 join 登录" '"alice"' "$(cat "${curl_log}")"
        assert_contains "bob 执行 join 登录" '"bob"' "$(cat "${curl_log}")"
        assert_contains "调用 joined_members 做成员验收" "/joined_members" "$(cat "${curl_log}")"
    else
        fail "创建成功用例" "script exits 0" "${output}"
    fi
}

echo ""
echo "=== CP2: 任一 worker 未 join 时必须失败 ==="
{
    workdir="$(mktemp -d "${TMPDIR_ROOT}/cp2-XXXXXX")"
    joined_members_file="${workdir}/joined-members.json"
    curl_log="${workdir}/curl.log"
    cat > "${joined_members_file}" <<'EOF'
{"joined":{"@manager:matrix.test":{},"@admin:matrix.test":{},"@alice:matrix.test":{}}}
EOF

    if output="$(run_create_project "${workdir}" "${joined_members_file}" "${curl_log}" 2>&1)"; then
        fail "成员缺失时应失败" "non-zero exit" "${output}"
    else
        assert_contains "失败输出指出成员不完整" "joined" "${output}"
    fi
}

echo ""
echo "=== Summary ==="
echo "PASS=${PASS}"
echo "FAIL=${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
