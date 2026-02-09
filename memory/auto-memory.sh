#!/bin/bash
# ============================================================================
# BoostDev Auto-Memory — Real-time Context Extraction
# Watches the session log and extracts key decisions, patterns, and context
# in real-time during a Claude Code session.
#
# Can run as:
#   - Background process during session
#   - Manual: boostdev memory auto
# ============================================================================

set -euo pipefail

BOOSTDEV_DIR="${HOME}/.boostdev"
CONFIG_FILE="${BOOSTDEV_DIR}/config/boostdev.conf"
LOG_DIR="${BOOSTDEV_DIR}/logs"
MEMORY_DIR="${BOOSTDEV_DIR}/memory/projects"
STATE_DIR="${BOOSTDEV_DIR}/state"
CURRENT_DATE=$(date +%Y%m%d)

# ── Load configuration ──────────────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

EXTRACT_DECISIONS="${BOOSTDEV_EXTRACT_DECISIONS:-true}"
COLOR_OUTPUT="${BOOSTDEV_COLOR_OUTPUT:-true}"

# ── Color helpers ────────────────────────────────────────────────────────────
if [[ "${COLOR_OUTPUT}" == "true" ]] && [[ -t 1 ]]; then
    GREEN='\033[1;32m'
    CYAN='\033[1;36m'
    DIM='\033[0;90m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' CYAN='' DIM='' YELLOW='' BOLD='' RESET=''
fi

# ── Get project name ────────────────────────────────────────────────────────
get_project_name() {
    if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
        basename "$(git rev-parse --show-toplevel)"
    else
        basename "${PWD}"
    fi
}

# ── Analyze session patterns ───────────────────────────────────────────────
analyze_session() {
    local session_log="${LOG_DIR}/session-${CURRENT_DATE}.jsonl"

    if [[ ! -f "${session_log}" ]]; then
        echo -e "${YELLOW}No session log found for today.${RESET}"
        return 1
    fi

    local project_name
    project_name=$(get_project_name)

    echo -e "${BOLD}Auto-Memory Analysis for '${project_name}'${RESET}"
    echo -e "${DIM}Session: $(date '+%Y-%m-%d')${RESET}"
    echo ""

    local total_calls
    total_calls=$(wc -l < "${session_log}" | tr -d ' ')
    echo -e "${CYAN}Total tool calls:${RESET} ${total_calls}"

    if command -v jq &>/dev/null; then
        # Tool breakdown
        echo ""
        echo -e "${BOLD}Tool Usage Breakdown:${RESET}"
        jq -r '.tool' "${session_log}" 2>/dev/null | sort | uniq -c | sort -rn | while read -r count tool; do
            local bar=""
            local bar_len=$(( count * 30 / total_calls ))
            for ((i=0; i<bar_len; i++)); do bar+="█"; done
            printf "  %-15s %3d  %s\n" "${tool}" "${count}" "${bar}"
        done

        # Error rate
        echo ""
        local error_count
        error_count=$(jq -r 'select(.has_error == true or .exit != 0) | .tool' "${session_log}" 2>/dev/null | wc -l | tr -d ' ')
        local error_rate=0
        if [[ "${total_calls}" -gt 0 ]]; then
            error_rate=$(( error_count * 100 / total_calls ))
        fi
        echo -e "${CYAN}Error rate:${RESET} ${error_count}/${total_calls} (${error_rate}%)"

        # Session duration
        local first_ts
        first_ts=$(head -1 "${session_log}" | jq -r '.ts' 2>/dev/null || echo "")
        local last_ts
        last_ts=$(tail -1 "${session_log}" | jq -r '.ts' 2>/dev/null || echo "")

        if [[ -n "${first_ts}" ]] && [[ -n "${last_ts}" ]]; then
            echo -e "${CYAN}Session span:${RESET} ${first_ts} to ${last_ts}"
        fi

        # Most active periods
        echo ""
        echo -e "${BOLD}Activity Timeline:${RESET}"
        jq -r '.ts' "${session_log}" 2>/dev/null | cut -dT -f2 | cut -d: -f1-2 | sort | uniq -c | sort -rn | head -5 | while read -r count hour; do
            printf "  %s  %d calls\n" "${hour}" "${count}"
        done

        # Loop incidents
        local loop_log="${BOOSTDEV_DIR}/stats/loops-${CURRENT_DATE}.jsonl"
        if [[ -f "${loop_log}" ]]; then
            local loop_count
            loop_count=$(wc -l < "${loop_log}" | tr -d ' ')
            echo ""
            echo -e "${YELLOW}Loop incidents today:${RESET} ${loop_count}"
        fi
    else
        echo ""
        echo -e "${DIM}Install jq for detailed analysis: brew install jq / apt install jq${RESET}"
    fi
}

# ── Generate structured memory entry ───────────────────────────────────────
generate_memory_entry() {
    local session_log="${LOG_DIR}/session-${CURRENT_DATE}.jsonl"
    local project_name
    project_name=$(get_project_name)
    local memory_file="${MEMORY_DIR}/${project_name}/auto-memory-${CURRENT_DATE}.md"

    mkdir -p "${MEMORY_DIR}/${project_name}"

    {
        echo "## Auto-Memory: $(date '+%Y-%m-%d %H:%M')"
        echo ""

        if [[ -f "${session_log}" ]] && command -v jq &>/dev/null; then
            local total_calls
            total_calls=$(wc -l < "${session_log}" | tr -d ' ')

            echo "### Session Statistics"
            echo "- Total tool calls: ${total_calls}"

            local error_count
            error_count=$(jq -r 'select(.has_error == true or .exit != 0) | .tool' "${session_log}" 2>/dev/null | wc -l | tr -d ' ')
            echo "- Errors encountered: ${error_count}"

            echo ""
            echo "### Tools Used"
            jq -r '.tool' "${session_log}" 2>/dev/null | sort | uniq -c | sort -rn | while read -r count tool; do
                echo "- ${tool}: ${count} calls"
            done

            local loop_log="${BOOSTDEV_DIR}/stats/loops-${CURRENT_DATE}.jsonl"
            if [[ -f "${loop_log}" ]]; then
                echo ""
                echo "### Loop Incidents"
                jq -r '"- \(.ts): \(.type) loop (session: \(.session))"' "${loop_log}" 2>/dev/null || true
            fi
        fi

        # Git changes
        if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
            echo ""
            echo "### Recent Git Activity"

            local today_commits
            today_commits=$(git log --oneline --since="today" 2>/dev/null || echo "")
            if [[ -n "${today_commits}" ]]; then
                echo "#### Commits Today"
                echo "${today_commits}" | while read -r line; do
                    echo "- ${line}"
                done
            fi

            local changed_files
            changed_files=$(git diff --stat 2>/dev/null || echo "")
            if [[ -n "${changed_files}" ]]; then
                echo "#### Uncommitted Changes"
                echo '```'
                echo "${changed_files}"
                echo '```'
            fi
        fi

        echo ""
        echo "---"
        echo ""
    } > "${memory_file}"

    echo -e "${GREEN}[BoostDev] Auto-memory saved: ${memory_file}${RESET}"
}

# ── Watch mode (background monitoring) ─────────────────────────────────────
watch_session() {
    local session_log="${LOG_DIR}/session-${CURRENT_DATE}.jsonl"
    local pid_file="${STATE_DIR}/auto-memory.pid"
    local last_line_count=0

    echo $$ > "${pid_file}"
    echo -e "${GREEN}[BoostDev] Auto-memory watcher started (PID: $$)${RESET}"

    trap 'rm -f "${pid_file}"; echo "[BoostDev] Auto-memory watcher stopped."; exit 0' INT TERM

    while true; do
        if [[ -f "${session_log}" ]]; then
            local current_count
            current_count=$(wc -l < "${session_log}" | tr -d ' ')

            if [[ "${current_count}" -gt "${last_line_count}" ]]; then
                local new_lines=$(( current_count - last_line_count ))

                # Every 20 new tool calls, generate a memory snapshot
                if [[ $(( current_count % 20 )) -lt "${new_lines}" ]]; then
                    generate_memory_entry
                fi

                last_line_count="${current_count}"
            fi
        fi

        sleep 30
    done
}

# ── Entry point ──────────────────────────────────────────────────────────────
case "${1:-analyze}" in
    analyze)
        analyze_session
        ;;
    save)
        generate_memory_entry
        ;;
    watch)
        watch_session
        ;;
    stop)
        pid_file="${STATE_DIR}/auto-memory.pid"
        if [[ -f "${pid_file}" ]]; then
            kill "$(cat "${pid_file}")" 2>/dev/null || true
            rm -f "${pid_file}"
            echo -e "${GREEN}[BoostDev] Auto-memory watcher stopped.${RESET}"
        else
            echo -e "${DIM}No watcher running.${RESET}"
        fi
        ;;
    *)
        echo "Usage: auto-memory.sh [analyze|save|watch|stop]"
        exit 1
        ;;
esac

exit 0
