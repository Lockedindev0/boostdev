#!/bin/bash
# ============================================================================
# BoostDev CLI — Main Entry Point
# Unified command-line interface for all BoostDev features
#
# Usage:
#   boostdev                    — Show help
#   boostdev stats              — Quick stats
#   boostdev report [--week]    — Usage report
#   boostdev memory show        — View saved context
#   boostdev loops              — Loop detection history
#   boostdev config             — Edit configuration
#   boostdev doctor             — Check installation health
#   boostdev version            — Show version
# ============================================================================

set -euo pipefail

BOOSTDEV_HOME="${HOME}/.boostdev"
CONFIG_FILE="${BOOSTDEV_HOME}/config/boostdev.conf"
VERSION_FILE="${BOOSTDEV_HOME}/VERSION"

# ── Load configuration ──────────────────────────────────────────────────────
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}" 2>/dev/null || true
fi

COLOR_OUTPUT="${BOOSTDEV_COLOR_OUTPUT:-true}"

# ── Colors ──────────────────────────────────────────────────────────────────
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

# ── Get version ─────────────────────────────────────────────────────────────
get_version() {
    if [[ -f "${VERSION_FILE}" ]]; then
        cat "${VERSION_FILE}"
    else
        echo "1.0.0"
    fi
}

# ── Help ────────────────────────────────────────────────────────────────────
show_help() {
    local version
    version=$(get_version)

    echo ""
    echo -e "${BOLD}BoostDev v${version}${RESET}"
    echo -e "${DIM}Supercharge your Claude Code — Kill loops, save tokens, remember everything.${RESET}"
    echo ""
    echo -e "${BOLD}USAGE${RESET}"
    echo -e "  ${CYAN}boostdev${RESET} <command> [options]"
    echo ""
    echo -e "${BOLD}COMMANDS${RESET}"
    echo -e "  ${CYAN}stats${RESET}                  Quick usage summary for today"
    echo -e "  ${CYAN}report${RESET} [--week|--month] Full usage report with breakdown"
    echo -e "  ${CYAN}memory show${RESET}             View saved session memory"
    echo -e "  ${CYAN}memory list${RESET}             List all projects with memory"
    echo -e "  ${CYAN}memory clear${RESET}            Clear memory for current project"
    echo -e "  ${CYAN}memory export${RESET}           Export memory as markdown file"
    echo -e "  ${CYAN}memory auto${RESET}             Run auto-memory analysis"
    echo -e "  ${CYAN}loops${RESET}                   Show loop detection history"
    echo -e "  ${CYAN}config${RESET}                  Open configuration in editor"
    echo -e "  ${CYAN}config set${RESET} KEY VALUE    Set a configuration value"
    echo -e "  ${CYAN}config show${RESET}             Show current configuration"
    echo -e "  ${CYAN}status${RESET}                  Show if hooks are active"
    echo -e "  ${CYAN}doctor${RESET}                  Check installation health"
    echo -e "  ${CYAN}update${RESET}                  Self-update from GitHub"
    echo -e "  ${CYAN}version${RESET}                 Show version number"
    echo -e "  ${CYAN}help${RESET}                    Show this help message"
    echo ""
    echo -e "${BOLD}EXAMPLES${RESET}"
    echo -e "  ${DIM}boostdev stats${RESET}                         # Quick daily summary"
    echo -e "  ${DIM}boostdev report --week${RESET}                 # Weekly usage report"
    echo -e "  ${DIM}boostdev memory show${RESET}                   # View project memory"
    echo -e "  ${DIM}boostdev config set MAX_REPEATS 5${RESET}      # Adjust loop threshold"
    echo ""
}

# ── Command: stats ──────────────────────────────────────────────────────────
cmd_stats() {
    if [[ -f "${BOOSTDEV_HOME}/dashboard/stats.sh" ]]; then
        bash "${BOOSTDEV_HOME}/dashboard/stats.sh"
    else
        echo -e "${RED}Stats script not found. Run install.sh first.${RESET}"
        exit 1
    fi
}

# ── Command: report ─────────────────────────────────────────────────────────
cmd_report() {
    if [[ -f "${BOOSTDEV_HOME}/dashboard/usage-report.sh" ]]; then
        bash "${BOOSTDEV_HOME}/dashboard/usage-report.sh" "$@"
    else
        echo -e "${RED}Report script not found. Run install.sh first.${RESET}"
        exit 1
    fi
}

# ── Command: memory ─────────────────────────────────────────────────────────
cmd_memory() {
    local subcmd="${1:-show}"
    shift 2>/dev/null || true

    case "${subcmd}" in
        show)
            bash "${BOOSTDEV_HOME}/memory/load-context.sh" show
            ;;
        list)
            bash "${BOOSTDEV_HOME}/memory/load-context.sh" list
            ;;
        clear)
            local project_name
            if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
                project_name=$(basename "$(git rev-parse --show-toplevel)")
            else
                project_name=$(basename "${PWD}")
            fi

            local memory_file="${BOOSTDEV_HOME}/memory/projects/${project_name}/context.md"

            if [[ -f "${memory_file}" ]]; then
                read -rp "Clear memory for '${project_name}'? (y/N) " reply
                if [[ "${reply}" =~ ^[Yy]$ ]]; then
                    rm -f "${memory_file}"
                    echo -e "${GREEN}Memory cleared for '${project_name}'.${RESET}"
                else
                    echo -e "${DIM}Cancelled.${RESET}"
                fi
            else
                echo -e "${DIM}No memory found for '${project_name}'.${RESET}"
            fi
            ;;
        export)
            local project_name
            if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
                project_name=$(basename "$(git rev-parse --show-toplevel)")
            else
                project_name=$(basename "${PWD}")
            fi

            local memory_file="${BOOSTDEV_HOME}/memory/projects/${project_name}/context.md"
            local export_file="${PWD}/boostdev-memory-export-$(date +%Y%m%d).md"

            if [[ -f "${memory_file}" ]]; then
                cp "${memory_file}" "${export_file}"
                echo -e "${GREEN}Memory exported to: ${export_file}${RESET}"
            else
                echo -e "${DIM}No memory found for '${project_name}'.${RESET}"
            fi
            ;;
        auto)
            bash "${BOOSTDEV_HOME}/memory/auto-memory.sh" analyze
            ;;
        save)
            bash "${BOOSTDEV_HOME}/memory/save-context.sh" --force
            ;;
        *)
            echo -e "${RED}Unknown memory command: ${subcmd}${RESET}"
            echo -e "Usage: boostdev memory [show|list|clear|export|auto|save]"
            exit 1
            ;;
    esac
}

# ── Command: loops ──────────────────────────────────────────────────────────
cmd_loops() {
    local stats_dir="${BOOSTDEV_HOME}/stats"
    local current_date
    current_date=$(date +%Y%m%d)

    echo ""
    echo -e "${BOLD}Loop Detection History${RESET}"
    echo ""

    local found=false

    # Show last 7 days of loop incidents
    for i in $(seq 0 6); do
        local d
        if date -d "-${i} days" +%Y%m%d &>/dev/null 2>&1; then
            d=$(date -d "-${i} days" +%Y%m%d)
        elif date -v-"${i}d" +%Y%m%d &>/dev/null 2>&1; then
            d=$(date -v-"${i}d" +%Y%m%d)
        else
            continue
        fi

        local loop_file="${stats_dir}/loops-${d}.jsonl"
        if [[ -f "${loop_file}" ]]; then
            found=true
            local count
            count=$(wc -l < "${loop_file}" | tr -d ' ')

            local date_display
            if [[ "${d}" == "${current_date}" ]]; then
                date_display="Today"
            else
                date_display="${d:0:4}-${d:4:2}-${d:6:2}"
            fi

            echo -e "  ${BOLD}${date_display}${RESET}: ${RED}${count}${RESET} loop(s) detected"

            if command -v jq &>/dev/null; then
                jq -r '"    - \(.ts | split("T")[1] | split("Z")[0]) \(.type) loop"' "${loop_file}" 2>/dev/null || true
            fi
        fi
    done

    if [[ "${found}" == "false" ]]; then
        echo -e "  ${GREEN}No loops detected in the last 7 days!${RESET}"
    fi

    echo ""
}

# ── Command: config ─────────────────────────────────────────────────────────
cmd_config() {
    local subcmd="${1:-edit}"
    shift 2>/dev/null || true

    case "${subcmd}" in
        edit)
            local editor="${EDITOR:-${VISUAL:-nano}}"
            "${editor}" "${CONFIG_FILE}"
            ;;
        show)
            echo ""
            echo -e "${BOLD}Current Configuration${RESET}"
            echo -e "${DIM}File: ${CONFIG_FILE}${RESET}"
            echo ""
            if [[ -f "${CONFIG_FILE}" ]]; then
                grep -v '^#' "${CONFIG_FILE}" | grep -v '^$' | while read -r line; do
                    local key
                    key=$(echo "${line}" | cut -d= -f1)
                    local value
                    value=$(echo "${line}" | cut -d= -f2-)
                    printf "  ${CYAN}%-30s${RESET} = %s\n" "${key}" "${value}"
                done
            else
                echo -e "  ${DIM}No configuration file found.${RESET}"
            fi
            echo ""
            ;;
        set)
            local key="${1:-}"
            local value="${2:-}"

            if [[ -z "${key}" ]] || [[ -z "${value}" ]]; then
                echo -e "${RED}Usage: boostdev config set KEY VALUE${RESET}"
                exit 1
            fi

            # Ensure key has BOOSTDEV_ prefix
            if [[ "${key}" != BOOSTDEV_* ]]; then
                key="BOOSTDEV_${key}"
            fi

            if [[ -f "${CONFIG_FILE}" ]]; then
                if grep -q "^${key}=" "${CONFIG_FILE}"; then
                    # Update existing key
                    sed -i.bak "s|^${key}=.*|${key}=${value}|" "${CONFIG_FILE}"
                    rm -f "${CONFIG_FILE}.bak"
                else
                    # Add new key
                    echo "${key}=${value}" >> "${CONFIG_FILE}"
                fi
            else
                echo "${key}=${value}" > "${CONFIG_FILE}"
            fi

            echo -e "${GREEN}Set ${key}=${value}${RESET}"
            ;;
        *)
            # Treat as 'edit' with no subcommand
            local editor="${EDITOR:-${VISUAL:-nano}}"
            "${editor}" "${CONFIG_FILE}"
            ;;
    esac
}

# ── Command: status ─────────────────────────────────────────────────────────
cmd_status() {
    echo ""
    echo -e "${BOLD}BoostDev Status${RESET}"
    echo ""

    # Check hook files
    echo -e "  ${BOLD}Hooks:${RESET}"
    for hook in anti-loop.sh token-tracker.sh pre-command.sh; do
        if [[ -f "${BOOSTDEV_HOME}/hooks/${hook}" ]] && [[ -x "${BOOSTDEV_HOME}/hooks/${hook}" ]]; then
            echo -e "    ${GREEN}${hook}${RESET} — active"
        else
            echo -e "    ${RED}${hook}${RESET} — not found or not executable"
        fi
    done

    # Check Claude settings
    echo ""
    echo -e "  ${BOLD}Claude Code Integration:${RESET}"
    local claude_settings="${HOME}/.claude/settings.json"
    if [[ -f "${claude_settings}" ]]; then
        if grep -q "boostdev" "${claude_settings}" 2>/dev/null; then
            echo -e "    ${GREEN}Hooks registered in Claude settings${RESET}"
        else
            echo -e "    ${YELLOW}Claude settings found but hooks not registered${RESET}"
        fi
    else
        echo -e "    ${RED}No Claude settings file found${RESET}"
    fi

    # Check memory system
    echo ""
    echo -e "  ${BOLD}Memory System:${RESET}"
    local memory_dir="${BOOSTDEV_HOME}/memory/projects"
    if [[ -d "${memory_dir}" ]]; then
        local project_count
        project_count=$(find "${memory_dir}" -name "context.md" 2>/dev/null | wc -l | tr -d ' ')
        echo -e "    ${GREEN}Active — ${project_count} projects tracked${RESET}"
    else
        echo -e "    ${DIM}No projects tracked yet${RESET}"
    fi

    # Check auto-memory watcher
    local pid_file="${BOOSTDEV_HOME}/state/auto-memory.pid"
    if [[ -f "${pid_file}" ]]; then
        local pid
        pid=$(cat "${pid_file}")
        if kill -0 "${pid}" 2>/dev/null; then
            echo -e "    ${GREEN}Auto-memory watcher running (PID: ${pid})${RESET}"
        else
            echo -e "    ${DIM}Auto-memory watcher not running${RESET}"
        fi
    else
        echo -e "    ${DIM}Auto-memory watcher not running${RESET}"
    fi

    # Check logs
    echo ""
    echo -e "  ${BOLD}Logs:${RESET}"
    local log_dir="${BOOSTDEV_HOME}/logs"
    if [[ -d "${log_dir}" ]]; then
        local log_count
        log_count=$(find "${log_dir}" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
        local log_size
        log_size=$(du -sh "${log_dir}" 2>/dev/null | cut -f1 || echo "0")
        echo -e "    ${GREEN}${log_count} log files (${log_size})${RESET}"
    else
        echo -e "    ${DIM}No logs yet${RESET}"
    fi

    echo ""
}

# ── Command: doctor ─────────────────────────────────────────────────────────
cmd_doctor() {
    echo ""
    echo -e "${BOLD}BoostDev Health Check${RESET}"
    echo ""

    local issues=0

    # Check installation directory
    if [[ -d "${BOOSTDEV_HOME}" ]]; then
        echo -e "  ${GREEN}Installation directory exists${RESET}"
    else
        echo -e "  ${RED}Installation directory missing: ${BOOSTDEV_HOME}${RESET}"
        issues=$(( issues + 1 ))
    fi

    # Check critical files
    for file in hooks/anti-loop.sh hooks/token-tracker.sh hooks/pre-command.sh \
                memory/save-context.sh memory/load-context.sh \
                dashboard/usage-report.sh dashboard/stats.sh; do
        if [[ -f "${BOOSTDEV_HOME}/${file}" ]]; then
            if [[ -x "${BOOSTDEV_HOME}/${file}" ]]; then
                echo -e "  ${GREEN}${file}${RESET}"
            else
                echo -e "  ${YELLOW}${file} — not executable${RESET}"
                issues=$(( issues + 1 ))
            fi
        else
            echo -e "  ${RED}${file} — missing${RESET}"
            issues=$(( issues + 1 ))
        fi
    done

    # Check config
    if [[ -f "${CONFIG_FILE}" ]]; then
        echo -e "  ${GREEN}Configuration file exists${RESET}"
    else
        echo -e "  ${YELLOW}Configuration file missing (using defaults)${RESET}"
    fi

    # Check dependencies
    echo ""
    echo -e "  ${BOLD}Dependencies:${RESET}"

    if command -v jq &>/dev/null; then
        echo -e "    ${GREEN}jq — installed${RESET}"
    else
        echo -e "    ${YELLOW}jq — not installed (some features limited)${RESET}"
        issues=$(( issues + 1 ))
    fi

    if command -v claude &>/dev/null; then
        echo -e "    ${GREEN}claude — installed${RESET}"
    else
        echo -e "    ${YELLOW}claude — not installed${RESET}"
    fi

    if command -v git &>/dev/null; then
        echo -e "    ${GREEN}git — installed${RESET}"
    else
        echo -e "    ${YELLOW}git — not installed${RESET}"
    fi

    # Check Claude Code settings
    echo ""
    echo -e "  ${BOLD}Claude Code Integration:${RESET}"
    local claude_settings="${HOME}/.claude/settings.json"
    if [[ -f "${claude_settings}" ]]; then
        if command -v jq &>/dev/null; then
            if jq -e '.hooks' "${claude_settings}" &>/dev/null; then
                echo -e "    ${GREEN}Hooks configured in settings.json${RESET}"
            else
                echo -e "    ${RED}Hooks not found in settings.json${RESET}"
                issues=$(( issues + 1 ))
            fi
        else
            if grep -q "hooks" "${claude_settings}" 2>/dev/null; then
                echo -e "    ${GREEN}Hooks appear configured${RESET}"
            else
                echo -e "    ${RED}Hooks not found in settings${RESET}"
                issues=$(( issues + 1 ))
            fi
        fi
    else
        echo -e "    ${RED}settings.json not found${RESET}"
        issues=$(( issues + 1 ))
    fi

    # Check writable directories
    echo ""
    echo -e "  ${BOLD}Permissions:${RESET}"
    for dir in logs stats state memory/projects; do
        local full_path="${BOOSTDEV_HOME}/${dir}"
        if [[ -d "${full_path}" ]] && [[ -w "${full_path}" ]]; then
            echo -e "    ${GREEN}${dir}/ — writable${RESET}"
        elif [[ -d "${full_path}" ]]; then
            echo -e "    ${RED}${dir}/ — not writable${RESET}"
            issues=$(( issues + 1 ))
        else
            echo -e "    ${YELLOW}${dir}/ — does not exist${RESET}"
        fi
    done

    # Summary
    echo ""
    if [[ "${issues}" -eq 0 ]]; then
        echo -e "  ${GREEN}All checks passed! BoostDev is healthy.${RESET}"
    else
        echo -e "  ${YELLOW}${issues} issue(s) found. Run install.sh to fix.${RESET}"
    fi
    echo ""
}

# ── Command: update ─────────────────────────────────────────────────────────
cmd_update() {
    echo -e "${CYAN}Checking for updates...${RESET}"

    # Find the source repo
    local source_dir=""

    # Check common locations
    for dir in "${PWD}" "${HOME}/boostdev" "${HOME}/projects/boostdev"; do
        if [[ -d "${dir}/.git" ]] && [[ -f "${dir}/install.sh" ]]; then
            source_dir="${dir}"
            break
        fi
    done

    if [[ -z "${source_dir}" ]]; then
        echo -e "${YELLOW}Could not find BoostDev source repository.${RESET}"
        echo -e "${DIM}Clone it first:${RESET}"
        echo -e "${DIM}  git clone https://github.com/Lockedindev0/boostdev.git${RESET}"
        echo -e "${DIM}  cd boostdev && git pull && ./install.sh${RESET}"
        exit 1
    fi

    echo -e "${DIM}Source directory: ${source_dir}${RESET}"

    # Pull latest
    cd "${source_dir}"
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || {
        echo -e "${RED}Could not pull updates. Check your git configuration.${RESET}"
        exit 1
    }

    # Re-run installer
    bash "${source_dir}/install.sh"
}

# ── Command: version ────────────────────────────────────────────────────────
cmd_version() {
    local version
    version=$(get_version)
    echo "BoostDev v${version}"
}

# ── Main router ─────────────────────────────────────────────────────────────
main() {
    local command="${1:-help}"
    shift 2>/dev/null || true

    case "${command}" in
        stats)      cmd_stats ;;
        report)     cmd_report "$@" ;;
        memory)     cmd_memory "$@" ;;
        loops)      cmd_loops ;;
        config)     cmd_config "$@" ;;
        status)     cmd_status ;;
        doctor)     cmd_doctor ;;
        update)     cmd_update ;;
        version|-v|--version)  cmd_version ;;
        help|-h|--help)        show_help ;;
        *)
            echo -e "${RED}Unknown command: ${command}${RESET}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
