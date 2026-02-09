#!/bin/bash
# ============================================================================
# BoostDev Anti-Loop Detection Hook
# Claude Code Post-Tool Hook for detecting and preventing infinite loops
#
# Environment variables from Claude Code hooks:
#   CLAUDE_TOOL_NAME    - name of the tool that was called
#   CLAUDE_TOOL_INPUT   - JSON input to the tool
#   CLAUDE_TOOL_OUTPUT  - output from the tool (stdout)
#   CLAUDE_TOOL_EXIT_CODE - exit code of the tool
#   CLAUDE_SESSION_ID   - current session ID
# ============================================================================

set -euo pipefail

BOOSTDEV_DIR="${HOME}/.boostdev"
LOG_DIR="${BOOSTDEV_DIR}/logs"
LOCK_DIR="${BOOSTDEV_DIR}/locks"
CURRENT_DATE=$(date +%Y%m%d)
CURRENT_LOG="${LOG_DIR}/session-${CURRENT_DATE}.jsonl"
CONFIG_FILE="${BOOSTDEV_DIR}/config/boostdev.conf"
LOOP_STATE="${BOOSTDEV_DIR}/state/loop-state.json"

# ── Load configuration ──────────────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

MAX_REPEATS="${BOOSTDEV_MAX_REPEATS:-3}"
LOOP_WINDOW="${BOOSTDEV_LOOP_WINDOW:-10}"
AUTO_INJECT="${BOOSTDEV_AUTO_INJECT:-true}"
LOOP_TIMEOUT="${BOOSTDEV_LOOP_TIMEOUT:-300}"
COLOR_OUTPUT="${BOOSTDEV_COLOR_OUTPUT:-true}"
SOUND_ALERT="${BOOSTDEV_SOUND_ALERT:-false}"

# ── Color helpers ────────────────────────────────────────────────────────────
if [[ "${COLOR_OUTPUT}" == "true" ]] && [[ -t 2 ]]; then
    RED='\033[1;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    DIM='\033[0;90m'
    GREEN='\033[1;32m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' YELLOW='' CYAN='' DIM='' GREEN='' BOLD='' RESET=''
fi

# ── Ensure directories exist ────────────────────────────────────────────────
mkdir -p "${LOG_DIR}" "${LOCK_DIR}" "${BOOSTDEV_DIR}/state" "${BOOSTDEV_DIR}/stats"

# ── Hash helper (portable across macOS/Linux) ───────────────────────────────
compute_hash() {
    local input="$1"
    if command -v md5sum &>/dev/null; then
        echo -n "${input}" | md5sum | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        echo -n "${input}" | md5 -q
    else
        # Fallback: use cksum
        echo -n "${input}" | cksum | cut -d' ' -f1
    fi
}

# ── Log the current tool call ───────────────────────────────────────────────
log_entry() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tool_name="${CLAUDE_TOOL_NAME:-unknown}"
    local tool_input="${CLAUDE_TOOL_INPUT:-}"
    local tool_output="${CLAUDE_TOOL_OUTPUT:-}"
    local exit_code="${CLAUDE_TOOL_EXIT_CODE:-0}"
    local session_id="${CLAUDE_SESSION_ID:-default}"

    # Extract error lines from output
    local error_lines
    error_lines=$(echo "${tool_output}" | grep -i "error\|fail\|exception\|traceback\|cannot\|not found\|denied" 2>/dev/null | head -5 || echo "")

    local error_hash
    error_hash=$(compute_hash "${error_lines}")

    local cmd_hash
    cmd_hash=$(compute_hash "${tool_name}:${tool_input}")

    # Build JSON entry (without jq dependency for logging)
    local json_entry
    json_entry=$(printf '{"ts":"%s","tool":"%s","exit":%s,"err_hash":"%s","cmd_hash":"%s","session":"%s","has_error":%s}' \
        "${timestamp}" \
        "${tool_name}" \
        "${exit_code}" \
        "${error_hash}" \
        "${cmd_hash}" \
        "${session_id}" \
        "$( [[ "${exit_code}" != "0" ]] && echo "true" || echo "false" )")

    echo "${json_entry}" >> "${CURRENT_LOG}"

    # Update session start time if not set
    local session_state="${BOOSTDEV_DIR}/state/session-start-${session_id}"
    if [[ ! -f "${session_state}" ]]; then
        echo "${timestamp}" > "${session_state}"
    fi
}

# ── Detect repeated error patterns ──────────────────────────────────────────
detect_error_loop() {
    if [[ ! -f "${CURRENT_LOG}" ]]; then
        return 1
    fi

    local recent
    recent=$(tail -n "${LOOP_WINDOW}" "${CURRENT_LOG}" 2>/dev/null || echo "")

    if [[ -z "${recent}" ]]; then
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        # Fallback: simple grep-based detection
        local err_hashes
        err_hashes=$(echo "${recent}" | grep -o '"err_hash":"[^"]*"' | sort | uniq -c | sort -rn | head -1)
        local top_count
        top_count=$(echo "${err_hashes}" | awk '{print $1}' | tr -d ' ')

        if [[ -n "${top_count}" ]] && [[ "${top_count}" -ge "${MAX_REPEATS}" ]]; then
            return 0
        fi
        return 1
    fi

    # With jq: precise detection
    # Only count entries that actually have errors
    local error_entries
    error_entries=$(echo "${recent}" | jq -r 'select(.has_error == true or .exit != 0) | .err_hash' 2>/dev/null || echo "")

    if [[ -z "${error_entries}" ]]; then
        return 1
    fi

    local top_count
    top_count=$(echo "${error_entries}" | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')

    if [[ -n "${top_count}" ]] && [[ "${top_count}" -ge "${MAX_REPEATS}" ]]; then
        return 0
    fi

    return 1
}

# ── Detect repeated command patterns ────────────────────────────────────────
detect_command_loop() {
    if [[ ! -f "${CURRENT_LOG}" ]]; then
        return 1
    fi

    local recent
    recent=$(tail -n "${LOOP_WINDOW}" "${CURRENT_LOG}" 2>/dev/null || echo "")

    if [[ -z "${recent}" ]]; then
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        local cmd_hashes
        cmd_hashes=$(echo "${recent}" | grep -o '"cmd_hash":"[^"]*"' | sort | uniq -c | sort -rn | head -1)
        local top_count
        top_count=$(echo "${cmd_hashes}" | awk '{print $1}' | tr -d ' ')

        if [[ -n "${top_count}" ]] && [[ "${top_count}" -ge "${MAX_REPEATS}" ]]; then
            return 0
        fi
        return 1
    fi

    local top_count
    top_count=$(echo "${recent}" | jq -r '.cmd_hash' 2>/dev/null | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')

    if [[ -n "${top_count}" ]] && [[ "${top_count}" -ge "${MAX_REPEATS}" ]]; then
        return 0
    fi

    return 1
}

# ── Detect time-based stalling ──────────────────────────────────────────────
detect_timeout() {
    local session_id="${CLAUDE_SESSION_ID:-default}"
    local session_state="${BOOSTDEV_DIR}/state/session-start-${session_id}"

    if [[ ! -f "${session_state}" ]]; then
        return 1
    fi

    local start_time
    start_time=$(cat "${session_state}")

    local start_epoch
    local now_epoch

    # Portable epoch calculation
    if date -d "2000-01-01" +%s &>/dev/null 2>&1; then
        # GNU date (Linux)
        start_epoch=$(date -d "${start_time}" +%s 2>/dev/null || echo "0")
        now_epoch=$(date +%s)
    elif date -j -f "%Y-%m-%dT%H:%M:%SZ" "2000-01-01T00:00:00Z" +%s &>/dev/null 2>&1; then
        # BSD date (macOS)
        start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${start_time}" +%s 2>/dev/null || echo "0")
        now_epoch=$(date +%s)
    else
        return 1
    fi

    local elapsed=$(( now_epoch - start_epoch ))

    if [[ "${elapsed}" -ge "${LOOP_TIMEOUT}" ]]; then
        return 0
    fi

    return 1
}

# ── Detect token burn rate spike ────────────────────────────────────────────
detect_burn_rate() {
    if [[ ! -f "${CURRENT_LOG}" ]]; then
        return 1
    fi

    local total_lines
    total_lines=$(wc -l < "${CURRENT_LOG}" | tr -d ' ')

    if [[ "${total_lines}" -lt 20 ]]; then
        return 1
    fi

    # Compare rate of last 5 calls vs overall average
    local recent_5_times
    if command -v jq &>/dev/null; then
        recent_5_times=$(tail -n 5 "${CURRENT_LOG}" | jq -r '.ts' 2>/dev/null | head -1)
        local oldest_time
        oldest_time=$(head -1 "${CURRENT_LOG}" | jq -r '.ts' 2>/dev/null)

        # Simple heuristic: if 5 calls happened in under 30 seconds, that's fast
        # This is a simplified check
        local recent_count
        recent_count=$(tail -n 5 "${CURRENT_LOG}" | jq -r 'select(.has_error == true) | .ts' 2>/dev/null | wc -l | tr -d ' ')

        if [[ "${recent_count}" -ge 4 ]]; then
            return 0
        fi
    fi

    return 1
}

# ── Record loop incident for stats ──────────────────────────────────────────
record_loop_incident() {
    local loop_type="$1"
    local stats_file="${BOOSTDEV_DIR}/stats/loops-${CURRENT_DATE}.jsonl"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local session_id="${CLAUDE_SESSION_ID:-default}"

    printf '{"ts":"%s","type":"%s","session":"%s","repeats":%s}\n' \
        "${timestamp}" "${loop_type}" "${session_id}" "${MAX_REPEATS}" \
        >> "${stats_file}"
}

# ── Play alert sound (optional) ─────────────────────────────────────────────
play_alert() {
    if [[ "${SOUND_ALERT}" == "true" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            afplay /System/Library/Sounds/Basso.aiff &>/dev/null &
        else
            printf '\a'
        fi
    fi
}

# ── Generate intervention message ───────────────────────────────────────────
generate_intervention() {
    local loop_type="$1"

    if [[ "${AUTO_INJECT}" == "true" ]]; then
        local msg="STOP. You are in a loop. "
        case "${loop_type}" in
            error)
                msg+="The same error has occurred ${MAX_REPEATS}+ times. "
                msg+="Do NOT retry the same approach. Step back, analyze WHY it's failing, "
                msg+="and try a completely different strategy."
                ;;
            command)
                msg+="You have run the same command ${MAX_REPEATS}+ times with the same failing result. "
                msg+="This approach is not working. Think about what's fundamentally wrong "
                msg+="and take a different path."
                ;;
            timeout)
                msg+="You have been working on this sub-task for too long without progress. "
                msg+="Break the problem down into smaller steps or ask the user for clarification."
                ;;
            burn_rate)
                msg+="Token consumption has spiked abnormally. Slow down and think through "
                msg+="the problem before making more tool calls."
                ;;
        esac
        echo "${msg}"
    fi
}

# ── Main execution ──────────────────────────────────────────────────────────

# Prevent re-entry
LOCK_FILE="${LOCK_DIR}/anti-loop.lock"
if [[ -f "${LOCK_FILE}" ]]; then
    lock_age=$(( $(date +%s) - $(stat -c %Y "${LOCK_FILE}" 2>/dev/null || stat -f %m "${LOCK_FILE}" 2>/dev/null || echo "0") ))
    if [[ "${lock_age}" -lt 2 ]]; then
        exit 0
    fi
fi
touch "${LOCK_FILE}"
trap 'rm -f "${LOCK_FILE}"' EXIT

# Log this tool call
log_entry

# Run detection checks
loop_detected=false
loop_type=""

if detect_error_loop; then
    loop_detected=true
    loop_type="error"
elif detect_command_loop; then
    loop_detected=true
    loop_type="command"
elif detect_burn_rate; then
    loop_detected=true
    loop_type="burn_rate"
fi

# Check timeout separately (warning, not blocking)
timeout_warning=false
if detect_timeout; then
    timeout_warning=true
fi

# ── Output results ──────────────────────────────────────────────────────────
if [[ "${loop_detected}" == "true" ]]; then
    record_loop_incident "${loop_type}"
    play_alert

    # Count redundant calls
    redundant_calls="${MAX_REPEATS}"

    echo "" >&2
    echo -e "${RED}[BoostDev] Loop Detected!${RESET}" >&2
    echo -e "${YELLOW}   Claude has repeated the same failing pattern ${MAX_REPEATS}+ times.${RESET}" >&2

    case "${loop_type}" in
        error)
            echo -e "${CYAN}   Type: Same error repeating${RESET}" >&2
            echo -e "${CYAN}   Suggestion: Ask Claude to analyze the root cause instead of retrying.${RESET}" >&2
            ;;
        command)
            echo -e "${CYAN}   Type: Same command repeating${RESET}" >&2
            echo -e "${CYAN}   Suggestion: The current approach isn't working. Try a different strategy.${RESET}" >&2
            ;;
        burn_rate)
            echo -e "${CYAN}   Type: Token burn rate spike${RESET}" >&2
            echo -e "${CYAN}   Suggestion: Claude is consuming tokens rapidly with errors. Slow down.${RESET}" >&2
            ;;
    esac

    echo -e "${DIM}   Session log: ${CURRENT_LOG}${RESET}" >&2
    echo -e "${YELLOW}   Estimated ${redundant_calls} redundant tool calls detected.${RESET}" >&2
    echo "" >&2

    # Output intervention message to stdout (for Claude to read)
    intervention=$(generate_intervention "${loop_type}")
    if [[ -n "${intervention}" ]]; then
        echo "${intervention}"
    fi
fi

if [[ "${timeout_warning}" == "true" ]]; then
    echo "" >&2
    echo -e "${YELLOW}[BoostDev] Time Warning${RESET}" >&2
    echo -e "${DIM}   Session has been running for over $((LOOP_TIMEOUT / 60)) minutes on this task.${RESET}" >&2
    echo -e "${CYAN}   Consider breaking the problem into smaller steps.${RESET}" >&2
    echo "" >&2
fi

exit 0
