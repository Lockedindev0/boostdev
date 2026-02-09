#!/bin/bash
# ============================================================================
# BoostDev Quick Stats
# One-liner summary of today's usage
#
# Usage: boostdev stats
# Output: Today: 142 calls | 7 loops killed | ~28K tokens | 23% saved
# ============================================================================

set -euo pipefail

BOOSTDEV_DIR="${HOME}/.boostdev"
CONFIG_FILE="${BOOSTDEV_DIR}/config/boostdev.conf"
STATS_DIR="${BOOSTDEV_DIR}/stats"
LOG_DIR="${BOOSTDEV_DIR}/logs"
CURRENT_DATE=$(date +%Y%m%d)

# ── Load configuration ──────────────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

COLOR_OUTPUT="${BOOSTDEV_COLOR_OUTPUT:-true}"

# ── Color helpers ────────────────────────────────────────────────────────────
if [[ "${COLOR_OUTPUT}" == "true" ]] && [[ -t 1 ]]; then
    GREEN='\033[1;32m'
    CYAN='\033[1;36m'
    YELLOW='\033[1;33m'
    RED='\033[1;31m'
    DIM='\033[0;90m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' CYAN='' YELLOW='' RED='' DIM='' BOLD='' RESET=''
fi

# ── Format number ──────────────────────────────────────────────────────────
format_number() {
    local num="$1"
    if [[ "${num}" -ge 1000000 ]]; then
        printf "%.1fM" "$(echo "scale=1; ${num}/1000000" | bc 2>/dev/null || echo "${num}")"
    elif [[ "${num}" -ge 1000 ]]; then
        printf "%.1fK" "$(echo "scale=1; ${num}/1000" | bc 2>/dev/null || echo "${num}")"
    else
        echo "${num}"
    fi
}

# ── Gather today's stats ──────────────────────────────────────────────────
total_calls=0
total_tokens=0
wasted_tokens=0
loops_killed=0

# From daily summary
summary="${STATS_DIR}/daily-summary-${CURRENT_DATE}.json"
if [[ -f "${summary}" ]] && command -v jq &>/dev/null; then
    total_calls=$(jq -r '.total_calls // 0' "${summary}" 2>/dev/null || echo "0")
    total_tokens=$(jq -r '.total_tokens // 0' "${summary}" 2>/dev/null || echo "0")
    wasted_tokens=$(jq -r '.wasted_tokens // 0' "${summary}" 2>/dev/null || echo "0")
elif [[ -f "${LOG_DIR}/session-${CURRENT_DATE}.jsonl" ]]; then
    total_calls=$(wc -l < "${LOG_DIR}/session-${CURRENT_DATE}.jsonl" | tr -d ' ')
    total_tokens=$(( total_calls * 200 ))
fi

# Loop incidents
loop_file="${STATS_DIR}/loops-${CURRENT_DATE}.jsonl"
if [[ -f "${loop_file}" ]]; then
    loops_killed=$(wc -l < "${loop_file}" | tr -d ' ')
fi

# Calculate savings
saved_tokens=$(( loops_killed * 1500 ))
savings_pct=0
if [[ $(( total_tokens + saved_tokens )) -gt 0 ]]; then
    savings_pct=$(( saved_tokens * 100 / (total_tokens + saved_tokens) ))
fi

# ── Output ──────────────────────────────────────────────────────────────────
if [[ "${total_calls}" -eq 0 ]]; then
    echo -e "${CYAN}BoostDev${RESET} ${DIM}| No activity today — start a Claude Code session!${RESET}"
    exit 0
fi

output="${GREEN}BoostDev${RESET}"
output+=" ${DIM}|${RESET} Today: ${BOLD}${total_calls}${RESET} calls"
output+=" ${DIM}|${RESET} "

if [[ "${loops_killed}" -gt 0 ]]; then
    output+="${RED}${loops_killed}${RESET} loops killed"
else
    output+="${GREEN}0${RESET} loops"
fi

output+=" ${DIM}|${RESET} ~${CYAN}$(format_number ${total_tokens})${RESET} tokens"

if [[ "${savings_pct}" -gt 0 ]]; then
    output+=" ${DIM}|${RESET} ${GREEN}${savings_pct}%${RESET} saved"
fi

echo -e "${output}"

exit 0
