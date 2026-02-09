#!/bin/bash
# ============================================================================
# BoostDev Uninstaller
# Cleanly removes all BoostDev files and configurations
#
# Usage: ./uninstall.sh [--force]
# ============================================================================

set -euo pipefail

BOOSTDEV_HOME="${HOME}/.boostdev"

# ── Colors ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[1;31m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    DIM='\033[0;90m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' DIM='' BOLD='' RESET=''
fi

echo ""
echo -e "${BOLD}BoostDev Uninstaller${RESET}"
echo ""

# ── Confirm unless --force ─────────────────────────────────────────────────
if [[ "${1:-}" != "--force" ]]; then
    echo -e "${YELLOW}This will remove all BoostDev files, including:${RESET}"
    echo -e "  - ${BOOSTDEV_HOME}/ (hooks, config, scripts)"
    echo -e "  - Session logs and statistics"
    echo -e "  - Saved session memory"
    echo -e "  - Claude Code hook registrations"
    echo -e "  - CLI symlinks"
    echo ""

    read -rp "Are you sure you want to uninstall BoostDev? (y/N) " reply
    if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
        echo -e "${DIM}Uninstall cancelled.${RESET}"
        exit 0
    fi

    echo ""

    # Offer to keep memory
    read -rp "Keep session memory data? (y/N) " keep_memory
    echo ""
fi

# ── Remove symlinks ────────────────────────────────────────────────────────
echo -e "${CYAN}Removing command shortcuts...${RESET}"

LOCAL_BIN="${HOME}/.local/bin"
SYSTEM_BIN="/usr/local/bin"

for cmd in boostdev boostdev-report boostdev-stats; do
    if [[ -L "${LOCAL_BIN}/${cmd}" ]]; then
        rm -f "${LOCAL_BIN}/${cmd}"
        echo -e "  ${DIM}Removed ${LOCAL_BIN}/${cmd}${RESET}"
    fi
    if [[ -L "${SYSTEM_BIN}/${cmd}" ]]; then
        sudo rm -f "${SYSTEM_BIN}/${cmd}" 2>/dev/null || {
            echo -e "  ${YELLOW}Could not remove ${SYSTEM_BIN}/${cmd} (may need sudo)${RESET}"
        }
        echo -e "  ${DIM}Removed ${SYSTEM_BIN}/${cmd}${RESET}"
    fi
done

echo -e "  ${GREEN}Symlinks removed${RESET}"

# ── Remove Claude Code hook configuration ──────────────────────────────────
echo -e "${CYAN}Removing Claude Code hook configuration...${RESET}"

CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
if [[ -f "${CLAUDE_SETTINGS}" ]] && command -v jq &>/dev/null; then
    # Remove BoostDev hooks from settings
    if jq 'has("hooks")' "${CLAUDE_SETTINGS}" 2>/dev/null | grep -q true; then
        # Remove hooks that reference boostdev
        jq 'del(.hooks)' "${CLAUDE_SETTINGS}" > "${CLAUDE_SETTINGS}.tmp" 2>/dev/null
        mv "${CLAUDE_SETTINGS}.tmp" "${CLAUDE_SETTINGS}"
        echo -e "  ${GREEN}Hook configuration removed from Claude settings${RESET}"
    fi
elif [[ -f "${CLAUDE_SETTINGS}" ]]; then
    echo -e "  ${YELLOW}Could not modify Claude settings (jq not found)${RESET}"
    echo -e "  ${DIM}Manually remove hooks from: ${CLAUDE_SETTINGS}${RESET}"
fi

# ── Backup memory if requested ─────────────────────────────────────────────
if [[ "${keep_memory:-n}" =~ ^[Yy]$ ]]; then
    BACKUP_DIR="${HOME}/boostdev-memory-backup-$(date +%Y%m%d-%H%M%S)"
    if [[ -d "${BOOSTDEV_HOME}/memory" ]]; then
        cp -r "${BOOSTDEV_HOME}/memory" "${BACKUP_DIR}"
        echo -e "${GREEN}Memory backed up to: ${BACKUP_DIR}${RESET}"
    fi
fi

# ── Stop background processes ──────────────────────────────────────────────
echo -e "${CYAN}Stopping background processes...${RESET}"

pid_file="${BOOSTDEV_HOME}/state/auto-memory.pid"
if [[ -f "${pid_file}" ]]; then
    kill "$(cat "${pid_file}")" 2>/dev/null || true
    echo -e "  ${DIM}Auto-memory watcher stopped${RESET}"
fi

# ── Remove BoostDev directory ──────────────────────────────────────────────
echo -e "${CYAN}Removing BoostDev files...${RESET}"

if [[ -d "${BOOSTDEV_HOME}" ]]; then
    rm -rf "${BOOSTDEV_HOME}"
    echo -e "  ${GREEN}Removed ${BOOSTDEV_HOME}/${RESET}"
fi

# ── Remove project-local .boostdev directories ────────────────────────────
echo -e "${CYAN}Checking for project-local files...${RESET}"

# Only clean current directory's .boostdev if it exists
if [[ -d "${PWD}/.boostdev" ]]; then
    read -rp "  Remove .boostdev/ in current project? (y/N) " clean_local
    if [[ "${clean_local:-n}" =~ ^[Yy]$ ]]; then
        rm -rf "${PWD}/.boostdev"
        echo -e "  ${GREEN}Removed ${PWD}/.boostdev/${RESET}"
    fi
fi

# ── Remove backups of Claude settings ─────────────────────────────────────
echo -e "${CYAN}Cleaning up backup files...${RESET}"

for backup in "${HOME}/.claude/settings.json.bak."*; do
    if [[ -f "${backup}" ]]; then
        rm -f "${backup}"
        echo -e "  ${DIM}Removed ${backup}${RESET}"
    fi
done

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  BoostDev has been uninstalled.${RESET}"
echo -e "${GREEN}════════════════════════════════════════════════════════${RESET}"
echo ""

if [[ "${keep_memory:-n}" =~ ^[Yy]$ ]] && [[ -d "${BACKUP_DIR:-/nonexistent}" ]]; then
    echo -e "  ${CYAN}Your memory data was saved to:${RESET}"
    echo -e "  ${DIM}  ${BACKUP_DIR}${RESET}"
    echo ""
fi

echo -e "  ${DIM}Thank you for using BoostDev!${RESET}"
echo ""

exit 0
