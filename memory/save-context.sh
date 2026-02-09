#!/bin/bash
# ============================================================================
# BoostDev Session Memory — Save Context
# Extracts and saves important decisions, file changes, and context
# from the current Claude Code session for future reference.
#
# Can run as:
#   - Post-session hook (automatic on session end)
#   - Manual: boostdev memory save
# ============================================================================

set -euo pipefail

BOOSTDEV_DIR="${HOME}/.boostdev"
CONFIG_FILE="${BOOSTDEV_DIR}/config/boostdev.conf"
LOG_DIR="${BOOSTDEV_DIR}/logs"
MEMORY_DIR="${BOOSTDEV_DIR}/memory/projects"
CURRENT_DATE=$(date +%Y%m%d)

# ── Load configuration ──────────────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

AUTO_SAVE="${BOOSTDEV_AUTO_SAVE:-true}"
MEMORY_MAX_SIZE="${BOOSTDEV_MEMORY_MAX_SIZE:-50}"
EXTRACT_DECISIONS="${BOOSTDEV_EXTRACT_DECISIONS:-true}"
COLOR_OUTPUT="${BOOSTDEV_COLOR_OUTPUT:-true}"

# ── Color helpers ────────────────────────────────────────────────────────────
if [[ "${COLOR_OUTPUT}" == "true" ]] && [[ -t 1 ]]; then
    GREEN='\033[1;32m'
    CYAN='\033[1;36m'
    DIM='\033[0;90m'
    YELLOW='\033[1;33m'
    RESET='\033[0m'
else
    GREEN='' CYAN='' DIM='' YELLOW='' RESET=''
fi

# ── Get project name ────────────────────────────────────────────────────────
get_project_name() {
    if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
        basename "$(git rev-parse --show-toplevel)"
    else
        basename "${PWD}"
    fi
}

# ── Extract decisions from session log ──────────────────────────────────────
extract_decisions() {
    local session_log="$1"

    if [[ ! -f "${session_log}" ]]; then
        return
    fi

    # Look for decision-related patterns in tool outputs
    local decisions=()

    if command -v jq &>/dev/null; then
        # Extract tool names and categorize the session activity
        local tool_counts
        tool_counts=$(jq -r '.tool' "${session_log}" 2>/dev/null | sort | uniq -c | sort -rn || echo "")

        if [[ -n "${tool_counts}" ]]; then
            echo "### Tool Usage"
            echo "${tool_counts}" | while read -r count tool; do
                echo "- ${tool}: ${count} calls"
            done
            echo ""
        fi

        # Extract error patterns that were resolved
        local error_entries
        error_entries=$(jq -r 'select(.has_error == true or .exit != 0) | .tool' "${session_log}" 2>/dev/null | sort | uniq -c | sort -rn || echo "")

        if [[ -n "${error_entries}" ]]; then
            echo "### Errors Encountered"
            echo "${error_entries}" | while read -r count tool; do
                echo "- ${tool}: ${count} errors"
            done
            echo ""
        fi
    fi
}

# ── Extract file changes from git ──────────────────────────────────────────
extract_file_changes() {
    if ! command -v git &>/dev/null; then
        return
    fi

    if ! git rev-parse --show-toplevel &>/dev/null 2>&1; then
        return
    fi

    echo "### Files Changed"

    # New/untracked files
    local new_files
    new_files=$(git ls-files --others --exclude-standard 2>/dev/null || echo "")
    if [[ -n "${new_files}" ]]; then
        echo "${new_files}" | while read -r f; do
            echo "- Created: ${f}"
        done
    fi

    # Modified files
    local modified_files
    modified_files=$(git diff --name-only 2>/dev/null || echo "")
    if [[ -n "${modified_files}" ]]; then
        echo "${modified_files}" | while read -r f; do
            echo "- Modified: ${f}"
        done
    fi

    # Staged files
    local staged_files
    staged_files=$(git diff --cached --name-only 2>/dev/null || echo "")
    if [[ -n "${staged_files}" ]]; then
        echo "${staged_files}" | while read -r f; do
            echo "- Staged: ${f}"
        done
    fi

    echo ""
}

# ── Extract current project state ──────────────────────────────────────────
extract_project_state() {
    echo "### Current State"

    # Check for common project files and their status
    if [[ -f "package.json" ]]; then
        local pkg_name
        pkg_name=$(jq -r '.name // "unknown"' package.json 2>/dev/null || echo "unknown")
        echo "- Node.js project: ${pkg_name}"
    fi

    if [[ -f "requirements.txt" ]]; then
        local dep_count
        dep_count=$(wc -l < requirements.txt | tr -d ' ')
        echo "- Python project with ${dep_count} dependencies"
    fi

    if [[ -f "Cargo.toml" ]]; then
        echo "- Rust project"
    fi

    if [[ -f "go.mod" ]]; then
        echo "- Go project"
    fi

    if [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        echo "- Docker Compose configured"
    fi

    if [[ -f ".env" ]]; then
        echo "- Environment file present (.env)"
    fi

    # Git branch info
    if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
        local branch
        branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        local commit_count
        commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        echo "- Git branch: ${branch} (${commit_count} commits)"
    fi

    echo ""
}

# ── Main save logic ────────────────────────────────────────────────────────
save_context() {
    local project_name
    project_name=$(get_project_name)
    local project_memory_dir="${MEMORY_DIR}/${project_name}"
    local context_file="${project_memory_dir}/context.md"
    local session_log="${LOG_DIR}/session-${CURRENT_DATE}.jsonl"

    mkdir -p "${project_memory_dir}"

    # Build session context
    local session_entry=""
    session_entry+="## Session: $(date '+%Y-%m-%d %H:%M')\n"
    session_entry+="\n"

    # Extract decisions from session log
    if [[ "${EXTRACT_DECISIONS}" == "true" ]] && [[ -f "${session_log}" ]]; then
        session_entry+="$(extract_decisions "${session_log}")\n"
    fi

    # Extract file changes
    session_entry+="$(extract_file_changes)\n"

    # Extract project state
    session_entry+="$(extract_project_state)\n"

    session_entry+="---\n\n"

    # Append to context file
    echo -e "${session_entry}" >> "${context_file}"

    # Trim if exceeds max size
    if [[ -f "${context_file}" ]]; then
        local section_count
        section_count=$(grep -c "^## Session:" "${context_file}" 2>/dev/null || echo "0")

        if [[ "${section_count}" -gt "${MEMORY_MAX_SIZE}" ]]; then
            # Keep only the most recent entries
            local temp_file="${context_file}.tmp"
            local keep_from=$(( section_count - MEMORY_MAX_SIZE ))

            # Extract header
            echo "# BoostDev Memory — ${project_name}" > "${temp_file}"
            echo "" >> "${temp_file}"

            # Keep recent sessions using awk
            awk -v skip="${keep_from}" '
                /^## Session:/ { count++ }
                count > skip { print }
            ' "${context_file}" >> "${temp_file}"

            mv "${temp_file}" "${context_file}"
        fi
    fi

    # Also save to project-local .boostdev/ if in a git repo
    if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
        local repo_root
        repo_root=$(git rev-parse --show-toplevel)
        local local_boostdev="${repo_root}/.boostdev"
        mkdir -p "${local_boostdev}"

        # Save a lightweight copy
        if [[ -f "${context_file}" ]]; then
            tail -100 "${context_file}" > "${local_boostdev}/context.md"
        fi
    fi

    echo -e "${GREEN}[BoostDev] Session context saved for '${project_name}'${RESET}"
    echo -e "${DIM}   Memory file: ${context_file}${RESET}"

    local line_count
    line_count=$(wc -l < "${context_file}" | tr -d ' ')
    echo -e "${DIM}   Total memory: ${line_count} lines${RESET}"
}

# ── Entry point ──────────────────────────────────────────────────────────────
if [[ "${AUTO_SAVE}" == "true" ]] || [[ "${1:-}" == "--force" ]]; then
    save_context
else
    echo -e "${YELLOW}[BoostDev] Auto-save disabled. Use --force to save anyway.${RESET}"
fi

exit 0
