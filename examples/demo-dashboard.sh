#!/bin/bash
# ============================================================================
# BoostDev Demo: Usage Dashboard
#
# This demo shows the token usage dashboard with sample data.
#
# Usage: bash examples/demo-dashboard.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="${SCRIPT_DIR}/../dashboard"

# Colors
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
DIM='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}BoostDev Demo: Usage Dashboard${RESET}"
echo -e "${DIM}This shows the dashboard with sample usage data.${RESET}"
echo ""

# Set up temporary environment with sample data
DEMO_DIR=$(mktemp -d)
export HOME_BACKUP="${HOME}"
export HOME="${DEMO_DIR}"

BOOSTDEV_HOME="${HOME}/.boostdev"
CURRENT_DATE=$(date +%Y%m%d)
mkdir -p "${BOOSTDEV_HOME}"/{logs,stats,config,state,memory/projects/my-app,dashboard}

# Create config
cat > "${BOOSTDEV_HOME}/config/boostdev.conf" << 'EOF'
BOOSTDEV_COLOR_OUTPUT=true
BOOSTDEV_SHOW_ESTIMATES=true
EOF

# Copy dashboard scripts
cp "${DASHBOARD_DIR}/usage-report.sh" "${BOOSTDEV_HOME}/dashboard/"
cp "${DASHBOARD_DIR}/stats.sh" "${BOOSTDEV_HOME}/dashboard/"

# Generate sample session log
echo -e "${CYAN}Generating sample usage data...${RESET}"
echo ""

SESSION_LOG="${BOOSTDEV_HOME}/logs/session-${CURRENT_DATE}.jsonl"
TOKEN_LOG="${BOOSTDEV_HOME}/stats/tokens-${CURRENT_DATE}.jsonl"

# Generate 142 sample tool calls
tools=("Read" "Edit" "Bash" "Grep" "Glob" "Write" "Read" "Edit" "Bash" "Read")
for i in $(seq 1 142); do
    tool_idx=$(( (i - 1) % ${#tools[@]} ))
    tool="${tools[$tool_idx]}"
    exit_code=0
    has_error=false

    # Make some calls fail (simulating errors)
    if [[ $(( i % 12 )) -eq 0 ]]; then
        exit_code=1
        has_error=true
    fi

    hour=$(( 9 + (i * 8 / 142) ))
    minute=$(( (i * 60 / 142) % 60 ))
    printf -v ts "2026-02-09T%02d:%02d:00Z" "${hour}" "${minute}"

    echo "{\"ts\":\"${ts}\",\"tool\":\"${tool}\",\"exit\":${exit_code},\"err_hash\":\"hash${i}\",\"cmd_hash\":\"cmd${i}\",\"session\":\"demo\",\"has_error\":${has_error}}" >> "${SESSION_LOG}"
done

# Generate daily summary
echo "{\"date\":\"${CURRENT_DATE}\",\"total_calls\":142,\"total_tokens\":28400,\"wasted_tokens\":3200}" > "${BOOSTDEV_HOME}/stats/daily-summary-${CURRENT_DATE}.json"

# Generate loop incidents
for i in 1 2 3 4 5 6 7; do
    hour=$(( 9 + i ))
    printf -v ts "2026-02-09T%02d:30:00Z" "${hour}"
    echo "{\"ts\":\"${ts}\",\"type\":\"error\",\"session\":\"demo\",\"repeats\":3}" >> "${BOOSTDEV_HOME}/stats/loops-${CURRENT_DATE}.jsonl"
done

# Create sample memory
echo "## Session: 2026-02-09" > "${BOOSTDEV_HOME}/memory/projects/my-app/context.md"

echo -e "${CYAN}Running quick stats...${RESET}"
echo ""

bash "${BOOSTDEV_HOME}/dashboard/stats.sh"

echo ""
echo -e "${CYAN}Running full report...${RESET}"

bash "${BOOSTDEV_HOME}/dashboard/usage-report.sh"

echo -e "${CYAN}Running weekly report...${RESET}"

bash "${BOOSTDEV_HOME}/dashboard/usage-report.sh" --week

# Cleanup
export HOME="${HOME_BACKUP}"
rm -rf "${DEMO_DIR}" 2>/dev/null || true

echo ""
echo -e "${BOLD}Demo complete!${RESET}"
echo -e "${DIM}Install BoostDev to get real usage tracking.${RESET}"
echo ""
