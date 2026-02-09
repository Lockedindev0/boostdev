#!/bin/bash
# ============================================================================
# BoostDev Token Tracker Hook
# Claude Code Post-Tool Hook for tracking token usage per tool call
#
# Estimates token consumption based on tool call input/output sizes
# and logs structured data for the dashboard.
# ============================================================================

set -euo pipefail

BOOSTDEV_DIR="${HOME}/.boostdev"
LOG_DIR="${BOOSTDEV_DIR}/logs"
STATS_DIR="${BOOSTDEV_DIR}/stats"
CONFIG_FILE="${BOOSTDEV_DIR}/config/boostdev.conf"
CURRENT_DATE=$(date +%Y%m%d)
TOKEN_LOG="${STATS_DIR}/tokens-${CURRENT_DATE}.jsonl"

# ── Load configuration ──────────────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

SHOW_ESTIMATES="${BOOSTDEV_SHOW_ESTIMATES:-true}"

# ── Ensure directories exist ────────────────────────────────────────────────
mkdir -p "${STATS_DIR}" "${LOG_DIR}"

# ── Estimate token count from text ──────────────────────────────────────────
# Rough estimation: ~4 characters per token for English text
estimate_tokens() {
    local text="$1"
    local char_count=${#text}
    echo $(( (char_count + 3) / 4 ))
}

# ── Get current project name ────────────────────────────────────────────────
get_project_name() {
    local cwd="${PWD}"
    # Try git repo name first
    if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
        basename "$(git rev-parse --show-toplevel)"
    else
        basename "${cwd}"
    fi
}

# ── Main tracking logic ────────────────────────────────────────────────────
track_usage() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tool_name="${CLAUDE_TOOL_NAME:-unknown}"
    local tool_input="${CLAUDE_TOOL_INPUT:-}"
    local tool_output="${CLAUDE_TOOL_OUTPUT:-}"
    local exit_code="${CLAUDE_TOOL_EXIT_CODE:-0}"
    local session_id="${CLAUDE_SESSION_ID:-default}"
    local project
    project=$(get_project_name)

    # Estimate tokens
    local input_tokens
    input_tokens=$(estimate_tokens "${tool_input}")
    local output_tokens
    output_tokens=$(estimate_tokens "${tool_output}")
    local total_tokens=$(( input_tokens + output_tokens ))

    # Determine if this was a wasted call (error/failure)
    local wasted=false
    if [[ "${exit_code}" != "0" ]]; then
        wasted=true
    fi

    # Classify the tool call
    local category="other"
    case "${tool_name}" in
        Bash|bash)          category="command" ;;
        Read|read)          category="read" ;;
        Write|write)        category="write" ;;
        Edit|edit)          category="edit" ;;
        Grep|grep)          category="search" ;;
        Glob|glob)          category="search" ;;
        WebFetch|WebSearch) category="web" ;;
        Task)               category="agent" ;;
        *)                  category="other" ;;
    esac

    # Build JSON log entry
    local entry
    entry=$(printf '{"ts":"%s","tool":"%s","category":"%s","input_tokens":%d,"output_tokens":%d,"total_tokens":%d,"wasted":%s,"exit":%s,"session":"%s","project":"%s"}' \
        "${timestamp}" \
        "${tool_name}" \
        "${category}" \
        "${input_tokens}" \
        "${output_tokens}" \
        "${total_tokens}" \
        "${wasted}" \
        "${exit_code}" \
        "${session_id}" \
        "${project}")

    echo "${entry}" >> "${TOKEN_LOG}"

    # Update daily summary
    update_daily_summary "${total_tokens}" "${wasted}"
}

# ── Update running daily summary ────────────────────────────────────────────
update_daily_summary() {
    local tokens="$1"
    local wasted="$2"
    local summary_file="${STATS_DIR}/daily-summary-${CURRENT_DATE}.json"

    if [[ -f "${summary_file}" ]] && command -v jq &>/dev/null; then
        local current
        current=$(cat "${summary_file}")
        local total_calls
        total_calls=$(echo "${current}" | jq -r '.total_calls')
        local total_tokens
        total_tokens=$(echo "${current}" | jq -r '.total_tokens')
        local wasted_tokens
        wasted_tokens=$(echo "${current}" | jq -r '.wasted_tokens')

        total_calls=$(( total_calls + 1 ))
        total_tokens=$(( total_tokens + tokens ))
        if [[ "${wasted}" == "true" ]]; then
            wasted_tokens=$(( wasted_tokens + tokens ))
        fi

        printf '{"date":"%s","total_calls":%d,"total_tokens":%d,"wasted_tokens":%d}' \
            "${CURRENT_DATE}" "${total_calls}" "${total_tokens}" "${wasted_tokens}" \
            > "${summary_file}"
    else
        local wasted_val=0
        if [[ "${wasted}" == "true" ]]; then
            wasted_val="${tokens}"
        fi
        printf '{"date":"%s","total_calls":1,"total_tokens":%d,"wasted_tokens":%d}' \
            "${CURRENT_DATE}" "${tokens}" "${wasted_val}" \
            > "${summary_file}"
    fi
}

# ── Execute ──────────────────────────────────────────────────────────────────
track_usage

exit 0
