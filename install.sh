#!/bin/bash
# ============================================================================
# BoostDev Installer
# One-command installation for BoostDev
#
# Usage:
#   git clone https://github.com/Lockedindev0/boostdev.git
#   cd boostdev && chmod +x install.sh && ./install.sh
# ============================================================================

set -euo pipefail

VERSION="1.0.0"
BOOSTDEV_HOME="${HOME}/.boostdev"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
echo -e "${BOLD}BoostDev Installer v${VERSION}${RESET}"
echo -e "${DIM}Supercharge your Claude Code — Kill loops, save tokens, remember everything.${RESET}"
echo ""

# ── Check prerequisites ────────────────────────────────────────────────────
echo -e "${CYAN}Checking prerequisites...${RESET}"

# Check for Claude Code
if command -v claude &>/dev/null; then
    echo -e "  ${GREEN}Claude Code found${RESET}"
else
    echo -e "  ${YELLOW}Claude Code not found (optional — hooks will activate when installed)${RESET}"
    echo -e "  ${DIM}Install: npm install -g @anthropic-ai/claude-code${RESET}"
fi

# Check for jq
if command -v jq &>/dev/null; then
    echo -e "  ${GREEN}jq found${RESET}"
else
    echo -e "  ${YELLOW}jq not found — some features will be limited${RESET}"
    echo ""
    echo -e "  ${BOLD}Install jq for full functionality:${RESET}"
    if [[ "$(uname)" == "Darwin" ]]; then
        echo -e "  ${DIM}  brew install jq${RESET}"
    else
        echo -e "  ${DIM}  sudo apt-get install -y jq${RESET}"
        echo -e "  ${DIM}  or: sudo yum install -y jq${RESET}"
    fi
    echo ""

    read -rp "  Continue without jq? (y/N) " reply
    if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Installation cancelled. Install jq first.${RESET}"
        exit 1
    fi
fi

# Check for bash version
bash_version="${BASH_VERSION%%(*}"
echo -e "  ${GREEN}Bash ${bash_version}${RESET}"

# Check OS
os_name=$(uname -s)
echo -e "  ${GREEN}OS: ${os_name}${RESET}"

echo ""

# ── Create directory structure ──────────────────────────────────────────────
echo -e "${CYAN}Creating directory structure...${RESET}"

mkdir -p "${BOOSTDEV_HOME}"/{hooks,memory/projects,dashboard,config,logs,stats,state,locks}

echo -e "  ${GREEN}Created ${BOOSTDEV_HOME}/${RESET}"

# ── Copy scripts ───────────────────────────────────────────────────────────
echo -e "${CYAN}Installing scripts...${RESET}"

# Hooks
if [[ -d "${SCRIPT_DIR}/hooks" ]]; then
    cp "${SCRIPT_DIR}/hooks/anti-loop.sh" "${BOOSTDEV_HOME}/hooks/"
    cp "${SCRIPT_DIR}/hooks/token-tracker.sh" "${BOOSTDEV_HOME}/hooks/"
    cp "${SCRIPT_DIR}/hooks/pre-command.sh" "${BOOSTDEV_HOME}/hooks/"
    echo -e "  ${GREEN}Hooks installed${RESET}"
fi

# Memory scripts
if [[ -d "${SCRIPT_DIR}/memory" ]]; then
    cp "${SCRIPT_DIR}/memory/save-context.sh" "${BOOSTDEV_HOME}/memory/"
    cp "${SCRIPT_DIR}/memory/load-context.sh" "${BOOSTDEV_HOME}/memory/"
    cp "${SCRIPT_DIR}/memory/auto-memory.sh" "${BOOSTDEV_HOME}/memory/"
    echo -e "  ${GREEN}Memory system installed${RESET}"
fi

# Dashboard
if [[ -d "${SCRIPT_DIR}/dashboard" ]]; then
    cp "${SCRIPT_DIR}/dashboard/usage-report.sh" "${BOOSTDEV_HOME}/dashboard/"
    cp "${SCRIPT_DIR}/dashboard/stats.sh" "${BOOSTDEV_HOME}/dashboard/"
    echo -e "  ${GREEN}Dashboard installed${RESET}"
fi

# CLI
if [[ -f "${SCRIPT_DIR}/boostdev-cli.sh" ]]; then
    cp "${SCRIPT_DIR}/boostdev-cli.sh" "${BOOSTDEV_HOME}/boostdev-cli.sh"
    echo -e "  ${GREEN}CLI installed${RESET}"
fi

# ── Set permissions ────────────────────────────────────────────────────────
echo -e "${CYAN}Setting permissions...${RESET}"

chmod +x "${BOOSTDEV_HOME}"/hooks/*.sh 2>/dev/null || true
chmod +x "${BOOSTDEV_HOME}"/memory/*.sh 2>/dev/null || true
chmod +x "${BOOSTDEV_HOME}"/dashboard/*.sh 2>/dev/null || true
chmod +x "${BOOSTDEV_HOME}"/boostdev-cli.sh 2>/dev/null || true

echo -e "  ${GREEN}Permissions set${RESET}"

# ── Install configuration ──────────────────────────────────────────────────
echo -e "${CYAN}Installing configuration...${RESET}"

if [[ -f "${SCRIPT_DIR}/config/boostdev.conf" ]]; then
    if [[ ! -f "${BOOSTDEV_HOME}/config/boostdev.conf" ]]; then
        cp "${SCRIPT_DIR}/config/boostdev.conf" "${BOOSTDEV_HOME}/config/"
        echo -e "  ${GREEN}Default configuration installed${RESET}"
    else
        echo -e "  ${DIM}Configuration already exists — keeping current${RESET}"
    fi
fi

# ── Save version ───────────────────────────────────────────────────────────
echo "${VERSION}" > "${BOOSTDEV_HOME}/VERSION"

# ── Create symlinks ────────────────────────────────────────────────────────
echo -e "${CYAN}Creating command shortcuts...${RESET}"

# Try user-local bin first, fall back to sudo
LOCAL_BIN="${HOME}/.local/bin"
SYSTEM_BIN="/usr/local/bin"
TARGET_BIN=""

if [[ -d "${LOCAL_BIN}" ]] || mkdir -p "${LOCAL_BIN}" 2>/dev/null; then
    TARGET_BIN="${LOCAL_BIN}"
    ln -sf "${BOOSTDEV_HOME}/boostdev-cli.sh" "${TARGET_BIN}/boostdev" 2>/dev/null || true
    ln -sf "${BOOSTDEV_HOME}/dashboard/usage-report.sh" "${TARGET_BIN}/boostdev-report" 2>/dev/null || true
    ln -sf "${BOOSTDEV_HOME}/dashboard/stats.sh" "${TARGET_BIN}/boostdev-stats" 2>/dev/null || true
    echo -e "  ${GREEN}Commands linked to ${TARGET_BIN}/${RESET}"

    # Check if LOCAL_BIN is in PATH
    if [[ ":${PATH}:" != *":${LOCAL_BIN}:"* ]]; then
        echo ""
        echo -e "  ${YELLOW}Add to your PATH (add to ~/.bashrc or ~/.zshrc):${RESET}"
        echo -e "  ${DIM}  export PATH=\"\${HOME}/.local/bin:\${PATH}\"${RESET}"
    fi
else
    echo -e "  ${DIM}Creating system symlinks (may require password)...${RESET}"
    sudo ln -sf "${BOOSTDEV_HOME}/boostdev-cli.sh" "${SYSTEM_BIN}/boostdev" 2>/dev/null || {
        echo -e "  ${YELLOW}Could not create symlinks. Add an alias instead:${RESET}"
        echo -e "  ${DIM}  alias boostdev='${BOOSTDEV_HOME}/boostdev-cli.sh'${RESET}"
    }
    TARGET_BIN="${SYSTEM_BIN}"
fi

# ── Configure Claude Code hooks ────────────────────────────────────────────
echo -e "${CYAN}Configuring Claude Code hooks...${RESET}"

CLAUDE_SETTINGS_DIR="${HOME}/.claude"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS_DIR}/settings.json"
mkdir -p "${CLAUDE_SETTINGS_DIR}"

# Build hook configuration
HOOK_CONFIG='{
  "hooks": {
    "PreToolCall": [
      {
        "matcher": ".*",
        "command": "'"${BOOSTDEV_HOME}"'/hooks/pre-command.sh"
      }
    ],
    "PostToolCall": [
      {
        "matcher": ".*",
        "command": "'"${BOOSTDEV_HOME}"'/hooks/anti-loop.sh"
      },
      {
        "matcher": ".*",
        "command": "'"${BOOSTDEV_HOME}"'/hooks/token-tracker.sh"
      }
    ],
    "SessionStart": [
      {
        "command": "'"${BOOSTDEV_HOME}"'/memory/load-context.sh load"
      }
    ],
    "SessionEnd": [
      {
        "command": "'"${BOOSTDEV_HOME}"'/memory/save-context.sh"
      }
    ]
  }
}'

if [[ -f "${CLAUDE_SETTINGS}" ]] && command -v jq &>/dev/null; then
    # Merge with existing settings
    local_backup="${CLAUDE_SETTINGS}.bak.$(date +%s)"
    cp "${CLAUDE_SETTINGS}" "${local_backup}"
    echo -e "  ${DIM}Existing settings backed up to: ${local_backup}${RESET}"

    # Deep merge hook config into existing settings
    jq -s '.[0] * .[1]' "${CLAUDE_SETTINGS}" <(echo "${HOOK_CONFIG}") > "${CLAUDE_SETTINGS}.tmp"
    mv "${CLAUDE_SETTINGS}.tmp" "${CLAUDE_SETTINGS}"
    echo -e "  ${GREEN}Hooks merged into existing Claude settings${RESET}"
else
    echo "${HOOK_CONFIG}" > "${CLAUDE_SETTINGS}"
    echo -e "  ${GREEN}Claude Code hook settings created${RESET}"
fi

# ── Copy .claude/settings.json template to repo ───────────────────────────
if [[ -d "${SCRIPT_DIR}/.claude" ]]; then
    cp "${SCRIPT_DIR}/.claude/settings.json" "${BOOSTDEV_HOME}/.claude-settings-template.json" 2>/dev/null || true
fi

# ── Generate CLAUDE.md template if it doesn't exist ────────────────────────
if [[ -f "${SCRIPT_DIR}/templates/CLAUDE.md.template" ]]; then
    if [[ ! -f "${PWD}/CLAUDE.md" ]]; then
        echo -e "${CYAN}Generating CLAUDE.md template...${RESET}"
        cp "${SCRIPT_DIR}/templates/CLAUDE.md.template" "${PWD}/CLAUDE.md" 2>/dev/null || true
        echo -e "  ${GREEN}CLAUDE.md created in current directory${RESET}"
    else
        echo -e "  ${DIM}CLAUDE.md already exists — skipping${RESET}"
    fi
fi

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  BoostDev installed successfully!${RESET}"
echo -e "${GREEN}════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Installed to:${RESET} ${BOOSTDEV_HOME}"
echo ""
echo -e "  ${BOLD}Quick Start:${RESET}"
echo -e "  ${CYAN}  boostdev stats${RESET}          — Quick usage summary"
echo -e "  ${CYAN}  boostdev report${RESET}         — Full usage report"
echo -e "  ${CYAN}  boostdev memory show${RESET}    — View saved context"
echo -e "  ${CYAN}  boostdev memory clear${RESET}   — Clear session memory"
echo -e "  ${CYAN}  boostdev config${RESET}         — Edit configuration"
echo -e "  ${CYAN}  boostdev doctor${RESET}         — Check installation health"
echo ""
echo -e "  ${RED}Anti-Loop${RESET} is now active automatically!"
echo -e "  ${CYAN}Session Memory${RESET} is now recording!"
echo ""
echo -e "  ${BOLD}Happy coding with BoostDev!${RESET}"
echo ""

exit 0
