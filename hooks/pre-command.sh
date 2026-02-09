#!/bin/bash
# ============================================================================
# BoostDev Pre-Command Optimizer Hook
# Claude Code Pre-Tool Hook for optimizing tool calls before execution
#
# This hook runs BEFORE each tool call and can:
# - Warn about potentially expensive operations
# - Inject optimization hints
# - Load session memory context
# - Track session start time
# ============================================================================

set -euo pipefail

BOOSTDEV_DIR="${HOME}/.boostdev"
CONFIG_FILE="${BOOSTDEV_DIR}/config/boostdev.conf"
STATE_DIR="${BOOSTDEV_DIR}/state"

# ── Load configuration ──────────────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

AUTO_LOAD="${BOOSTDEV_AUTO_LOAD:-true}"
COLOR_OUTPUT="${BOOSTDEV_COLOR_OUTPUT:-true}"

# ── Color helpers ────────────────────────────────────────────────────────────
if [[ "${COLOR_OUTPUT}" == "true" ]] && [[ -t 2 ]]; then
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    DIM='\033[0;90m'
    GREEN='\033[1;32m'
    RESET='\033[0m'
else
    YELLOW='' CYAN='' DIM='' GREEN='' RESET=''
fi

# ── Ensure directories ──────────────────────────────────────────────────────
mkdir -p "${STATE_DIR}"

# ── Track session start ─────────────────────────────────────────────────────
track_session_start() {
    local session_id="${CLAUDE_SESSION_ID:-default}"
    local session_marker="${STATE_DIR}/session-active-${session_id}"

    if [[ ! -f "${session_marker}" ]]; then
        date -u +"%Y-%m-%dT%H:%M:%SZ" > "${session_marker}"

        # First tool call of session — show status
        echo "" >&2
        echo -e "${GREEN}[BoostDev] Session started${RESET}" >&2

        # Show loaded memory if available
        if [[ "${AUTO_LOAD}" == "true" ]]; then
            local project_name
            if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
                project_name=$(basename "$(git rev-parse --show-toplevel)")
            else
                project_name=$(basename "${PWD}")
            fi

            local memory_file="${BOOSTDEV_DIR}/memory/projects/${project_name}/context.md"
            if [[ -f "${memory_file}" ]]; then
                local line_count
                line_count=$(wc -l < "${memory_file}" | tr -d ' ')
                echo -e "${CYAN}   Session memory loaded (${line_count} lines from previous sessions)${RESET}" >&2
            fi
        fi

        # Show today's stats if available
        local stats_file="${BOOSTDEV_DIR}/stats/daily-summary-$(date +%Y%m%d).json"
        if [[ -f "${stats_file}" ]] && command -v jq &>/dev/null; then
            local calls
            calls=$(jq -r '.total_calls' "${stats_file}" 2>/dev/null || echo "0")
            local tokens
            tokens=$(jq -r '.total_tokens' "${stats_file}" 2>/dev/null || echo "0")
            echo -e "${DIM}   Today so far: ${calls} calls, ~${tokens} tokens${RESET}" >&2
        fi

        echo "" >&2
    fi
}

# ── Warn about expensive operations ─────────────────────────────────────────
check_expensive_ops() {
    local tool_name="${CLAUDE_TOOL_NAME:-unknown}"
    local tool_input="${CLAUDE_TOOL_INPUT:-}"

    case "${tool_name}" in
        Bash|bash)
            # Warn about potentially destructive or expensive commands
            if echo "${tool_input}" | grep -qiE "rm -rf|drop table|truncate|delete from|format|mkfs" 2>/dev/null; then
                echo "" >&2
                echo -e "${YELLOW}[BoostDev] Destructive command detected!${RESET}" >&2
                echo -e "${DIM}   Please verify this is intentional.${RESET}" >&2
                echo "" >&2
            fi

            # Warn about commands that might generate huge output
            if echo "${tool_input}" | grep -qiE "find / |cat.*\.log$|tail -f" 2>/dev/null; then
                echo "" >&2
                echo -e "${YELLOW}[BoostDev] This command may generate large output.${RESET}" >&2
                echo -e "${DIM}   Consider using head/tail to limit output size.${RESET}" >&2
                echo "" >&2
            fi
            ;;
        WebFetch|WebSearch)
            # Track web calls (these are expensive)
            echo -e "${DIM}[BoostDev] Web operation — higher token cost${RESET}" >&2
            ;;
    esac
}

# ── Main execution ──────────────────────────────────────────────────────────
track_session_start
check_expensive_ops

exit 0
