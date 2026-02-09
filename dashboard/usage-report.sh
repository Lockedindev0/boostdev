#!/bin/bash
# ============================================================================
# BoostDev Usage Report Dashboard
# Terminal-based token usage report with detailed breakdowns.
#
# Usage:
#   boostdev report           — Today's report
#   boostdev report --week    — This week's report
#   boostdev report --month   — This month's report
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
    RED='\033[1;31m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    BLUE='\033[1;34m'
    DIM='\033[0;90m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BLUE='' DIM='' BOLD='' RESET=''
fi

# ── Parse arguments ─────────────────────────────────────────────────────────
PERIOD="today"
case "${1:-}" in
    --week|-w)   PERIOD="week" ;;
    --month|-m)  PERIOD="month" ;;
    --all|-a)    PERIOD="all" ;;
    *)           PERIOD="today" ;;
esac

# ── Helper: format numbers with commas ──────────────────────────────────────
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

# ── Helper: get date list for period ────────────────────────────────────────
get_date_range() {
    local period="$1"
    local dates=()

    case "${period}" in
        today)
            dates+=("${CURRENT_DATE}")
            ;;
        week)
            for i in $(seq 0 6); do
                if date -d "-${i} days" +%Y%m%d &>/dev/null 2>&1; then
                    dates+=("$(date -d "-${i} days" +%Y%m%d)")
                elif date -v-"${i}d" +%Y%m%d &>/dev/null 2>&1; then
                    dates+=("$(date -v-"${i}d" +%Y%m%d)")
                fi
            done
            ;;
        month)
            for i in $(seq 0 29); do
                if date -d "-${i} days" +%Y%m%d &>/dev/null 2>&1; then
                    dates+=("$(date -d "-${i} days" +%Y%m%d)")
                elif date -v-"${i}d" +%Y%m%d &>/dev/null 2>&1; then
                    dates+=("$(date -v-"${i}d" +%Y%m%d)")
                fi
            done
            ;;
        all)
            if [[ -d "${STATS_DIR}" ]]; then
                for f in "${STATS_DIR}"/tokens-*.jsonl; do
                    if [[ -f "${f}" ]]; then
                        local d
                        d=$(basename "${f}" | sed 's/tokens-//; s/.jsonl//')
                        dates+=("${d}")
                    fi
                done
            fi
            ;;
    esac

    echo "${dates[@]}"
}

# ── Aggregate stats for date range ──────────────────────────────────────────
aggregate_stats() {
    local dates
    dates=$(get_date_range "${PERIOD}")

    local total_calls=0
    local total_tokens=0
    local wasted_tokens=0
    local total_loops=0
    local memory_loads=0

    for d in ${dates}; do
        # From daily summary
        local summary="${STATS_DIR}/daily-summary-${d}.json"
        if [[ -f "${summary}" ]] && command -v jq &>/dev/null; then
            local dc dt dw
            dc=$(jq -r '.total_calls // 0' "${summary}" 2>/dev/null || echo "0")
            dt=$(jq -r '.total_tokens // 0' "${summary}" 2>/dev/null || echo "0")
            dw=$(jq -r '.wasted_tokens // 0' "${summary}" 2>/dev/null || echo "0")
            total_calls=$(( total_calls + dc ))
            total_tokens=$(( total_tokens + dt ))
            wasted_tokens=$(( wasted_tokens + dw ))
        elif [[ -f "${LOG_DIR}/session-${d}.jsonl" ]]; then
            local dc
            dc=$(wc -l < "${LOG_DIR}/session-${d}.jsonl" | tr -d ' ')
            total_calls=$(( total_calls + dc ))
            total_tokens=$(( total_tokens + dc * 200 ))  # rough estimate
        fi

        # Loop incidents
        local loop_file="${STATS_DIR}/loops-${d}.jsonl"
        if [[ -f "${loop_file}" ]]; then
            local lc
            lc=$(wc -l < "${loop_file}" | tr -d ' ')
            total_loops=$(( total_loops + lc ))
        fi
    done

    # Estimate savings from loops killed
    local saved_tokens=$(( total_loops * 1500 ))  # ~1500 tokens per avoided loop iteration

    echo "${total_calls}|${total_tokens}|${wasted_tokens}|${total_loops}|${saved_tokens}"
}

# ── Get top consumers ──────────────────────────────────────────────────────
get_top_consumers() {
    local token_log="${STATS_DIR}/tokens-${CURRENT_DATE}.jsonl"

    if [[ ! -f "${token_log}" ]] || ! command -v jq &>/dev/null; then
        return
    fi

    jq -r '.category' "${token_log}" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | while read -r count category; do
        local estimated_tokens=$(( count * 200 ))
        printf "   %-25s — ~%s tokens\n" "${category}" "$(format_number ${estimated_tokens})"
    done
}

# ── Get tool breakdown ──────────────────────────────────────────────────────
get_tool_breakdown() {
    local dates
    dates=$(get_date_range "${PERIOD}")

    local combined_tools=""

    for d in ${dates}; do
        local log="${LOG_DIR}/session-${d}.jsonl"
        if [[ -f "${log}" ]] && command -v jq &>/dev/null; then
            combined_tools+=$(jq -r '.tool' "${log}" 2>/dev/null)
            combined_tools+=$'\n'
        fi
    done

    if [[ -n "${combined_tools}" ]]; then
        echo "${combined_tools}" | grep -v '^$' | sort | uniq -c | sort -rn | head -8
    fi
}

# ── Draw the report ─────────────────────────────────────────────────────────
draw_report() {
    local stats
    stats=$(aggregate_stats)

    local total_calls total_tokens wasted_tokens total_loops saved_tokens
    IFS='|' read -r total_calls total_tokens wasted_tokens total_loops saved_tokens <<< "${stats}"

    local period_label
    case "${PERIOD}" in
        today) period_label="Today" ;;
        week)  period_label="This Week" ;;
        month) period_label="This Month" ;;
        all)   period_label="All Time" ;;
    esac

    local savings_pct=0
    if [[ "${total_tokens}" -gt 0 ]]; then
        savings_pct=$(( saved_tokens * 100 / (total_tokens + saved_tokens) ))
    fi

    # ── Header ──────────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║             BoostDev Usage Report                   ║${RESET}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"

    # ── Period stats ────────────────────────────────────────────────────
    printf "${BOLD}║${RESET}  %-12s │ %-40s ${BOLD}║${RESET}\n" "Period" "${period_label}"
    printf "${BOLD}║${RESET}  %-12s │ %-40s ${BOLD}║${RESET}\n" "Tool Calls" "$(format_number ${total_calls})"
    printf "${BOLD}║${RESET}  %-12s │ ~%-39s ${BOLD}║${RESET}\n" "Tokens" "$(format_number ${total_tokens})"

    if [[ "${wasted_tokens}" -gt 0 ]]; then
        printf "${BOLD}║${RESET}  ${RED}%-12s${RESET} │ ${RED}~%-39s${RESET} ${BOLD}║${RESET}\n" "Wasted" "$(format_number ${wasted_tokens})"
    fi

    echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"

    # ── Loop detection stats ────────────────────────────────────────────
    if [[ "${total_loops}" -gt 0 ]]; then
        printf "${BOLD}║${RESET}  ${RED}Loops Killed:${RESET} %-38s ${BOLD}║${RESET}\n" "${total_loops} (saved ~$(format_number ${saved_tokens}) tokens)"
    else
        printf "${BOLD}║${RESET}  ${GREEN}Loops Killed:${RESET} %-38s ${BOLD}║${RESET}\n" "0 — smooth sailing!"
    fi

    # Memory loads
    local memory_dir="${BOOSTDEV_DIR}/memory/projects"
    local project_count=0
    if [[ -d "${memory_dir}" ]]; then
        project_count=$(find "${memory_dir}" -name "context.md" 2>/dev/null | wc -l | tr -d ' ')
    fi
    printf "${BOLD}║${RESET}  ${CYAN}Memory:${RESET} %-44s ${BOLD}║${RESET}\n" "${project_count} projects with saved context"

    echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"

    # ── Tool breakdown ──────────────────────────────────────────────────
    printf "${BOLD}║${RESET}  ${BOLD}Tool Breakdown:${RESET}%-37s ${BOLD}║${RESET}\n" ""

    local breakdown
    breakdown=$(get_tool_breakdown)
    if [[ -n "${breakdown}" ]]; then
        echo "${breakdown}" | while read -r count tool; do
            local bar=""
            local max_bar=20
            local bar_len
            if [[ "${total_calls}" -gt 0 ]]; then
                bar_len=$(( count * max_bar / total_calls ))
            else
                bar_len=0
            fi
            for ((i=0; i<bar_len; i++)); do bar+="█"; done
            for ((i=bar_len; i<max_bar; i++)); do bar+="░"; done
            printf "${BOLD}║${RESET}  %-10s %4d  %s ${BOLD}║${RESET}\n" "${tool}" "${count}" "${bar}"
        done
    else
        printf "${BOLD}║${RESET}  %-52s ${BOLD}║${RESET}\n" "  No data available"
    fi

    echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${RESET}"

    # ── Savings ─────────────────────────────────────────────────────────
    if [[ "${saved_tokens}" -gt 0 ]]; then
        printf "${BOLD}║${RESET}  ${GREEN}Estimated Savings: ~%s tokens (%d%% reduction)${RESET}" "$(format_number ${saved_tokens})" "${savings_pct}"
        # Pad to fit box
        local msg="Estimated Savings: ~$(format_number ${saved_tokens}) tokens (${savings_pct}% reduction)"
        local pad=$(( 51 - ${#msg} ))
        printf "%*s${BOLD}║${RESET}\n" "${pad}" ""
    else
        printf "${BOLD}║${RESET}  ${DIM}%-52s${RESET} ${BOLD}║${RESET}\n" "Start using Claude Code to see savings!"
    fi

    echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ── Entry point ──────────────────────────────────────────────────────────────
draw_report

exit 0
