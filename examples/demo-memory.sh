#!/bin/bash
# ============================================================================
# BoostDev Demo: Session Memory
#
# This demo shows how BoostDev saves and loads session context
# between Claude Code sessions.
#
# Usage: bash examples/demo-memory.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_DIR="${SCRIPT_DIR}/../memory"

# Colors
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
DIM='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}BoostDev Demo: Session Memory${RESET}"
echo -e "${DIM}This shows how BoostDev preserves context between sessions.${RESET}"
echo ""

# Set up temporary environment
DEMO_DIR=$(mktemp -d)
export HOME_BACKUP="${HOME}"
export HOME="${DEMO_DIR}"

BOOSTDEV_HOME="${HOME}/.boostdev"
mkdir -p "${BOOSTDEV_HOME}"/{memory/projects/demo-project,logs,config,state}

# Create config
cat > "${BOOSTDEV_HOME}/config/boostdev.conf" << 'EOF'
BOOSTDEV_AUTO_SAVE=true
BOOSTDEV_AUTO_LOAD=true
BOOSTDEV_MEMORY_MAX_SIZE=50
BOOSTDEV_EXTRACT_DECISIONS=true
BOOSTDEV_COLOR_OUTPUT=true
EOF

# Create a fake session log
cat > "${BOOSTDEV_HOME}/logs/session-$(date +%Y%m%d).jsonl" << 'EOF'
{"ts":"2026-02-09T10:00:00Z","tool":"Read","exit":0,"err_hash":"d41d8cd","cmd_hash":"abc123","session":"demo","has_error":false}
{"ts":"2026-02-09T10:01:00Z","tool":"Edit","exit":0,"err_hash":"d41d8cd","cmd_hash":"def456","session":"demo","has_error":false}
{"ts":"2026-02-09T10:02:00Z","tool":"Bash","exit":1,"err_hash":"e5f6a7b","cmd_hash":"ghi789","session":"demo","has_error":true}
{"ts":"2026-02-09T10:03:00Z","tool":"Edit","exit":0,"err_hash":"d41d8cd","cmd_hash":"jkl012","session":"demo","has_error":false}
{"ts":"2026-02-09T10:04:00Z","tool":"Bash","exit":0,"err_hash":"d41d8cd","cmd_hash":"mno345","session":"demo","has_error":false}
EOF

# Create a pre-existing memory file
cat > "${BOOSTDEV_HOME}/memory/projects/demo-project/context.md" << 'EOF'
## Session: 2026-02-08 09:15

### Decisions Made
- Using FastAPI instead of Flask for better async support
- PostgreSQL with SQLAlchemy ORM for the database layer
- JWT tokens for API authentication
- Redis for session caching

### Files Changed
- Created: src/api/routes.py, src/models/user.py, src/auth/jwt.py
- Modified: requirements.txt, docker-compose.yml, .env.example

### Errors Resolved
- Fixed CORS issue by adding FastAPI CORSMiddleware
- Resolved circular import in models by using lazy loading

### Current State
- User CRUD API endpoints complete
- JWT auth middleware working
- Docker Compose setup with PostgreSQL + Redis
- TODO: Add rate limiting, write unit tests, set up CI/CD

---

## Session: 2026-02-08 14:30

### Decisions Made
- Added pytest for testing framework
- Using httpx for async test client
- Implemented repository pattern for data access

### Files Changed
- Created: tests/test_users.py, tests/conftest.py, src/repositories/user_repo.py
- Modified: src/api/routes.py (refactored to use repository)

### Current State
- 12 unit tests passing
- Repository pattern implemented for User model
- TODO: Add integration tests, implement rate limiting

---

EOF

echo -e "${CYAN}Step 1: Simulating session start (loading memory)...${RESET}"
echo ""

# Simulate loading context
cd "${DEMO_DIR}"
mkdir -p "demo-project"
cd "demo-project"

echo -e "${DIM}Loading memory for project 'demo-project'...${RESET}"
echo ""

# Show what would be loaded
echo -e "${GREEN}=== BoostDev Session Memory ===${RESET}"
echo -e "${DIM}Previous session context for project 'demo-project':${RESET}"
echo ""
cat "${BOOSTDEV_HOME}/memory/projects/demo-project/context.md"

echo -e "${GREEN}=== End BoostDev Memory ===${RESET}"
echo ""

echo -e "${CYAN}Step 2: Claude now has full context from previous sessions!${RESET}"
echo ""
echo -e "  ${GREEN}Claude knows:${RESET}"
echo -e "  - FastAPI + PostgreSQL + Redis stack"
echo -e "  - JWT authentication is implemented"
echo -e "  - 12 tests passing with pytest"
echo -e "  - Next task: rate limiting and integration tests"
echo ""

echo -e "${CYAN}Step 3: Simulating session end (saving new context)...${RESET}"
echo ""

# Add new session entry
cat >> "${BOOSTDEV_HOME}/memory/projects/demo-project/context.md" << EOF
## Session: $(date '+%Y-%m-%d %H:%M')

### Decisions Made
- Added rate limiting with slowapi library
- Implemented Redis-based rate limit storage
- Using 100 req/min for authenticated, 20 req/min for anonymous

### Files Changed
- Created: src/middleware/rate_limit.py, tests/test_rate_limit.py
- Modified: src/api/routes.py, requirements.txt

### Current State
- Rate limiting fully implemented
- 18 tests passing
- TODO: Set up GitHub Actions CI/CD, add API documentation

---

EOF

echo -e "${GREEN}New session context saved!${RESET}"
echo ""
echo -e "${DIM}Memory file now contains 3 sessions of context.${RESET}"
echo -e "${DIM}Next session will load all of this automatically.${RESET}"

# Cleanup
export HOME="${HOME_BACKUP}"
rm -rf "${DEMO_DIR}" 2>/dev/null || true

echo ""
echo -e "${BOLD}Demo complete!${RESET}"
echo -e "${DIM}With BoostDev, Claude never starts from zero.${RESET}"
echo ""
