#!/bin/sh
# hiclaw-find-skill.sh - Unified skill discovery wrapper for Workers
# Backends:
#   - skills_sh: delegate to `skills find`
#   - nacos: query local/default Nacos CLI profile and render skills-style output

set -eu

BACKEND="${HICLAW_FIND_SKILL_BACKEND:-nacos}"
MAX_RESULTS="${HICLAW_FIND_SKILL_MAX_RESULTS:-6}"
PAGE_SIZE="${HICLAW_FIND_SKILL_NACOS_PAGE_SIZE:-100}"

RESET='[0m'
DIM='[38;5;102m'
TEXT='[38;5;145m'
GRAY_0='[38;5;250m'
GRAY_1='[38;5;248m'
GRAY_2='[38;5;245m'
GRAY_3='[38;5;243m'
GRAY_4='[38;5;240m'
GRAY_5='[38;5;238m'

show_logo() {
    printf '\n'
    printf '%s%s%s\n' "${GRAY_0}" '███████╗██╗  ██╗██╗██╗     ██╗     ███████╗' "${RESET}"
    printf '%s%s%s\n' "${GRAY_1}" '██╔════╝██║ ██╔╝██║██║     ██║     ██╔════╝' "${RESET}"
    printf '%s%s%s\n' "${GRAY_2}" '███████╗█████╔╝ ██║██║     ██║     ███████╗' "${RESET}"
    printf '%s%s%s\n' "${GRAY_3}" '╚════██║██╔═██╗ ██║██║     ██║     ╚════██║' "${RESET}"
    printf '%s%s%s\n' "${GRAY_4}" '███████║██║  ██╗██║███████╗███████╗███████║' "${RESET}"
    printf '%s%s%s\n' "${GRAY_5}" '╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚══════╝' "${RESET}"
    printf '\n'
}

usage() {
    cat <<'EOF'
Usage:
  hiclaw-find-skill find <query>
  hiclaw-find-skill install <skill>

Environment:
  HICLAW_FIND_SKILL_BACKEND=nacos|skills_sh   Default: nacos
  SKILLS_API_URL                              Used by skills.sh backend when configured
EOF
}

run_skills_find() {
    exec skills find "$@"
}

run_skills_install() {
    if [ $# -lt 1 ]; then
        echo "error: skill name is required for install" >&2
        exit 1
    fi
    exec skills add "$1" -g -y
}

run_nacos_install() {
    if [ $# -lt 1 ]; then
        echo "error: skill name is required for install" >&2
        exit 1
    fi
    exec npx -y @nacos-group/cli skill-get "$1"
}

run_nacos_find() {
    if [ $# -lt 1 ]; then
        show_logo
        printf '%sTip:%s search with %shiclaw-find-skill find <query>%s\n' "${DIM}" "${RESET}" "${TEXT}" "${RESET}"
        exit 0
    fi

    query="$*"
    query_lc="$(printf '%s' "${query}" | tr '[:upper:]' '[:lower:]')"
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT INT TERM
    raw_first="${tmp_dir}/page1.txt"
    all_numbered="${tmp_dir}/all-numbered.txt"
    scored="${tmp_dir}/scored.txt"
    sorted="${tmp_dir}/sorted.txt"

    raw_output="$(npx -y @nacos-group/cli skill-list --page 1 --size "${PAGE_SIZE}" 2>&1)" || {
        printf '%s\n' "${raw_output}" >&2
        exit 1
    }
    printf '%s\n' "${raw_output}" > "${raw_first}"

    total="$(printf '%s\n' "${raw_output}" | sed -n 's/^Skill List (Total: \([0-9][0-9]*\)).*/\1/p' | head -n 1)"
    if [ -z "${total}" ]; then
        total=0
    fi

    total_pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))
    if [ "${total_pages}" -lt 1 ]; then
        total_pages=1
    fi

    : > "${all_numbered}"
    printf '%s\n' "${raw_output}" | grep -E '^[[:space:]]*[0-9]+\.[[:space:]]' >> "${all_numbered}" || true

    page=2
    while [ "${page}" -le "${total_pages}" ]; do
        page_output="$(npx -y @nacos-group/cli skill-list --page "${page}" --size "${PAGE_SIZE}" 2>&1)" || {
            printf '%s\n' "${page_output}" >&2
            exit 1
        }
        printf '%s\n' "${page_output}" | grep -E '^[[:space:]]*[0-9]+\.[[:space:]]' >> "${all_numbered}" || true
        page=$((page + 1))
    done

    awk -v query="${query_lc}" '
        function lower(s) { return tolower(s) }
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        BEGIN {
            tokenCount = split(query, rawTokens, /[[:space:]]+/)
            q = lower(query)
        }
        /^[[:space:]]*[0-9]+\.[[:space:]]/ {
            line = $0
            sub(/^[[:space:]]*[0-9]+\.[[:space:]]+/, "", line)
            name = line
            desc = ""
            splitPos = index(line, " - ")
            if (splitPos > 0) {
                name = substr(line, 1, splitPos - 1)
                desc = substr(line, splitPos + 3)
            }

            name = trim(name)
            desc = trim(desc)
            lname = lower(name)
            ldesc = lower(desc)
            hay = lname " " ldesc

            if (q == "") next

            score = 0
            matched = 0

            if (lname == q) score += 1000
            if (index(lname, q) > 0) score += 500
            if (index(ldesc, q) > 0) score += 120

            for (i = 1; i <= tokenCount; i++) {
                token = trim(rawTokens[i])
                if (token == "") continue
                if (index(hay, token) == 0) {
                    matched = -1
                    break
                }
                matched = 1
                if (index(lname, token) > 0) score += 80
                if (index(ldesc, token) > 0) score += 20
            }

            if (matched != 1 && index(hay, q) == 0) next
            printf "%08d\t%s\t%s\n", score, name, desc
        }
    ' "${all_numbered}" > "${scored}"

    sort -r "${scored}" > "${sorted}"

    show_logo

    if [ ! -s "${sorted}" ]; then
        printf '%sNo skills found for "%s"%s\n' "${DIM}" "${query}" "${RESET}"
        exit 0
    fi

    first_name="$(awk -F '\t' 'NR == 1 { print $2; exit }' "${sorted}")"

    printf '%sInstall with%s %shiclaw-find-skill install %s%s\n\n' \
        "${DIM}" "${RESET}" "${TEXT}" "${first_name}" "${RESET}"

    sed -n "1,${MAX_RESULTS}p" "${sorted}" | while IFS="$(printf '\t')" read -r score name desc; do
        if [ -z "${desc}" ]; then
            desc="Available from Nacos skill registry"
        fi

        printf '%s%s%s\n' "${TEXT}" "${name}" "${RESET}"
        printf '%s└ %s%s\n\n' "${DIM}" "${desc}" "${RESET}"
    done
}

command_name="${1:-find}"
if [ $# -gt 0 ]; then
    shift
fi

case "${command_name}" in
    find)
        case "${BACKEND}" in
            skills_sh) run_skills_find "$@" ;;
            nacos) run_nacos_find "$@" ;;
            *)
                echo "error: unsupported HICLAW_FIND_SKILL_BACKEND=${BACKEND}" >&2
                exit 1
                ;;
        esac
        ;;
    install|get)
        case "${BACKEND}" in
            skills_sh) run_skills_install "$@" ;;
            nacos) run_nacos_install "$@" ;;
            *)
                echo "error: unsupported HICLAW_FIND_SKILL_BACKEND=${BACKEND}" >&2
                exit 1
                ;;
        esac
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "error: unknown command: ${command_name}" >&2
        usage >&2
        exit 1
        ;;
esac
