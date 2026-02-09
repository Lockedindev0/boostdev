#!/bin/bash
# ============================================================================
# BoostDev Session Memory — Load Context
# Loads previous session context at the start of a new Claude Code session.
# Injects relevant memory so Claude doesn't start from scratch.
#
# Can run as:
#   - Pre-session hook (automatic on session start)
#   - Manual: boostdev memory show
# ============================================================================

set -euo pipefail

BOOSTDEV_DIR="${HOME}/.boostdev"
CONFIG_FILE="${BOOSTDEV_DIR}/config/boostdev.conf"
MEMORY_DIR="${BOOSTDEV_DIR}/memory/projects"

# ── Load configuration ──────────────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

AUTO_LOAD="${BOOSTDEV_AUTO_LOAD:-true}"
COLOR_OUTPUT="${BOOSTDEV_COLOR_OUTPUT:-true}"

# ── Color helpers ────────────────────────────────────────────────────────────
if [[ "${COLOR_OUTPUT}" == "true" ]] && [[ -t 2 ]]; then
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

# ── Load and display context ───────────────────────────────────────────────
load_context() {
    local project_name
    project_name=$(get_project_name)
    local context_file="${MEMORY_DIR}/${project_name}/context.md"

    # Also check project-local .boostdev/context.md
    local local_context=""
    if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
        local repo_root
        repo_root=$(git rev-parse --show-toplevel)
        local local_file="${repo_root}/.boostdev/context.md"
        if [[ -f "${local_file}" ]]; then
            local_context="${local_file}"
        fi
    fi

    # Determine which context file to use
    local active_context=""
    if [[ -f "${context_file}" ]]; then
        active_context="${context_file}"
    elif [[ -n "${local_context}" ]]; then
        active_context="${local_context}"
    fi

    if [[ -z "${active_context}" ]]; then
        echo -e "${DIM}[BoostDev] No previous session memory found for '${project_name}'.${RESET}" >&2
        echo -e "${DIM}   Memory will be saved automatically when this session ends.${RESET}" >&2
        return 0
    fi

    # Get the last 3 sessions for context injection
    local recent_context
    recent_context=$(extract_recent_sessions "${active_context}" 3)

    if [[ -n "${recent_context}" ]]; then
        # Output to stderr for user visibility
        echo "" >&2
        echo -e "${GREEN}[BoostDev] Loading session memory for '${project_name}'${RESET}" >&2
        echo -e "${DIM}   Source: ${active_context}${RESET}" >&2
        echo "" >&2

        # Output to stdout for Claude to read as context
        echo "=== BoostDev Session Memory ==="
        echo "Previous session context for project '${project_name}':"
        echo ""
        echo "${recent_context}"
        echo ""
        echo "=== End BoostDev Memory ==="
    fi
}

# ── Extract N most recent sessions ─────────────────────────────────────────
extract_recent_sessions() {
    local file="$1"
    local count="$2"

    if [[ ! -f "${file}" ]]; then
        return
    fi

    # Count total sessions
    local total_sessions
    total_sessions=$(grep -c "^## Session:" "${file}" 2>/dev/null || echo "0")

    if [[ "${total_sessions}" -eq 0 ]]; then
        return
    fi

    local skip=0
    if [[ "${total_sessions}" -gt "${count}" ]]; then
        skip=$(( total_sessions - count ))
    fi

    # Extract recent sessions using awk
    awk -v skip="${skip}" '
        /^## Session:/ { session_num++ }
        session_num > skip { print }
    ' "${file}"
}

# ── Show full memory (for CLI command) ──────────────────────────────────────
show_full_memory() {
    local project_name
    project_name=$(get_project_name)
    local context_file="${MEMORY_DIR}/${project_name}/context.md"

    if [[ ! -f "${context_file}" ]]; then
        echo -e "${YELLOW}No memory found for project '${project_name}'.${RESET}"
        echo -e "${DIM}Start a Claude Code session to begin recording memory.${RESET}"
        return 1
    fi

    echo -e "${BOLD}Session Memory for '${project_name}'${RESET}"
    echo -e "${DIM}File: ${context_file}${RESET}"
    echo ""

    cat "${context_file}"

    echo ""
    local line_count
    line_count=$(wc -l < "${context_file}" | tr -d ' ')
    local session_count
    session_count=$(grep -c "^## Session:" "${context_file}" 2>/dev/null || echo "0")
    echo -e "${DIM}${session_count} sessions, ${line_count} lines total${RESET}"
}

# ── List all projects with memory ──────────────────────────────────────────
list_projects() {
    echo -e "${BOLD}Projects with saved memory:${RESET}"
    echo ""

    if [[ ! -d "${MEMORY_DIR}" ]]; then
        echo -e "${DIM}  No projects found.${RESET}"
        return
    fi

    for project_dir in "${MEMORY_DIR}"/*/; do
        if [[ -d "${project_dir}" ]]; then
            local name
            name=$(basename "${project_dir}")
            local context_file="${project_dir}/context.md"

            if [[ -f "${context_file}" ]]; then
                local sessions
                sessions=$(grep -c "^## Session:" "${context_file}" 2>/dev/null || echo "0")
                local lines
                lines=$(wc -l < "${context_file}" | tr -d ' ')
                local last_modified
                last_modified=$(date -r "${context_file}" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "${context_file}" 2>/dev/null | cut -d. -f1 || echo "unknown")

                echo -e "  ${CYAN}${name}${RESET} — ${sessions} sessions, ${lines} lines (last: ${last_modified})"
            fi
        fi
    done
}

# ── Entry point ──────────────────────────────────────────────────────────────
case "${1:-load}" in
    load)
        if [[ "${AUTO_LOAD}" == "true" ]] || [[ "${2:-}" == "--force" ]]; then
            load_context
        fi
        ;;
    show)
        show_full_memory
        ;;
    list)
        list_projects
        ;;
    *)
        echo "Usage: load-context.sh [load|show|list]"
        exit 1
        ;;
esac

exit 0
