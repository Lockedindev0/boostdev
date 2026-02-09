#!/bin/bash
# ============================================================================
# BoostDev Demo: Anti-Loop Detection
#
# This demo simulates Claude Code entering a loop and shows how
# BoostDev detects and intervenes.
#
# Usage: bash examples/demo-anti-loop.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/../hooks"

# Colors
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
DIM='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}BoostDev Demo: Anti-Loop Detection${RESET}"
echo -e "${DIM}This simulates Claude Code stuck in a loop.${RESET}"
echo ""

# Set up temporary environment
export BOOSTDEV_DIR=$(mktemp -d)
export BOOSTDEV_MAX_REPEATS=3
export BOOSTDEV_LOOP_WINDOW=5
export BOOSTDEV_AUTO_INJECT=true
export BOOSTDEV_COLOR_OUTPUT=true
export BOOSTDEV_SOUND_ALERT=false
export CLAUDE_SESSION_ID="demo-session"

mkdir -p "${BOOSTDEV_DIR}"/{logs,stats,state,locks,config}

# Create minimal config
cat > "${BOOSTDEV_DIR}/config/boostdev.conf" << 'EOF'
BOOSTDEV_MAX_REPEATS=3
BOOSTDEV_LOOP_WINDOW=5
BOOSTDEV_AUTO_INJECT=true
BOOSTDEV_COLOR_OUTPUT=true
BOOSTDEV_SOUND_ALERT=false
EOF

# Override HOME for the demo
export HOME_BACKUP="${HOME}"
export HOME="${BOOSTDEV_DIR%/.boostdev}"
mkdir -p "${HOME}/.boostdev"
cp -r "${BOOSTDEV_DIR}"/* "${HOME}/.boostdev/" 2>/dev/null || true

echo -e "${CYAN}Step 1: Simulating normal tool calls...${RESET}"
echo ""

# Simulate successful calls
for i in 1 2 3; do
    export CLAUDE_TOOL_NAME="Bash"
    export CLAUDE_TOOL_INPUT="npm test"
    export CLAUDE_TOOL_OUTPUT="All tests passed (${i}/3)"
    export CLAUDE_TOOL_EXIT_CODE="0"

    bash "${HOOKS_DIR}/anti-loop.sh" 2>&1 || true
    echo -e "  ${GREEN}Call ${i}: Success — no loop detected${RESET}"
    sleep 0.3
done

echo ""
echo -e "${CYAN}Step 2: Simulating repeated failures (loop scenario)...${RESET}"
echo ""

# Simulate the same error repeating
for i in 1 2 3 4; do
    export CLAUDE_TOOL_NAME="Bash"
    export CLAUDE_TOOL_INPUT="npm run build"
    export CLAUDE_TOOL_OUTPUT="Error: Module not found: './utils/helpers'
  at Object.<anonymous> (src/index.js:5:1)
  Cannot find module './utils/helpers'"
    export CLAUDE_TOOL_EXIT_CODE="1"

    echo -e "  ${YELLOW}Call ${i}: Same build error...${RESET}"
    output=$(bash "${HOOKS_DIR}/anti-loop.sh" 2>&1) || true
    echo "${output}"

    if echo "${output}" | grep -q "Loop Detected"; then
        echo ""
        echo -e "${GREEN}BoostDev caught the loop after ${i} attempts!${RESET}"
        break
    fi

    sleep 0.5
done

echo ""
echo -e "${CYAN}Step 3: Checking session log...${RESET}"
echo ""

log_file=$(find "${HOME}/.boostdev/logs" -name "session-*.jsonl" 2>/dev/null | head -1)
if [[ -n "${log_file}" ]] && [[ -f "${log_file}" ]]; then
    echo -e "${DIM}Session log entries:${RESET}"
    cat "${log_file}" | head -10
else
    echo -e "${DIM}(Log file created at ~/.boostdev/logs/)${RESET}"
fi

# Cleanup
export HOME="${HOME_BACKUP}"
rm -rf "${BOOSTDEV_DIR}" 2>/dev/null || true

echo ""
echo -e "${BOLD}Demo complete!${RESET}"
echo -e "${DIM}Install BoostDev to get this protection in every Claude Code session.${RESET}"
echo ""
