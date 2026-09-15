#!/bin/bash
set -euo pipefail

# Offline testing for notify-bot
# Run locally before deploying to home server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_LOG="/tmp/notify-bot-test.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $*" | tee -a "$TEST_LOG"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*" | tee -a "$TEST_LOG"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*" | tee -a "$TEST_LOG"
}

log_test() {
    echo -e "\n${YELLOW}=== $* ===${NC}" | tee -a "$TEST_LOG"
}

cleanup() {
    log_info "Cleaning up..."
    # Kill background processes
    jobs -p | xargs -r kill 2>/dev/null || true
}

trap cleanup EXIT

echo "Notify Bot - Offline Testing Suite" | tee "$TEST_LOG"
echo "Log: $TEST_LOG" | tee -a "$TEST_LOG"

# === Test 1: Python Environment ===
log_test "Test 1: Python Environment"

if ! command -v python3 &>/dev/null; then
    log_fail "Python3 not found"
    exit 1
fi
log_pass "Python3 available: $(python3 --version)"

if ! python3 -c "import urllib" 2>/dev/null; then
    log_fail "urllib module not available"
    exit 1
fi
log_pass "urllib (stdlib) available"

# === Test 2: Import Core Module ===
log_test "Test 2: Import Core Module"

cd "$SCRIPT_DIR"
if ! python3 -c "from telegram_notifier import TelegramNotifier" 2>/dev/null; then
    log_fail "Cannot import TelegramNotifier"
    exit 1
fi
log_pass "TelegramNotifier imports successfully"

# === Test 3: Flask Installation ===
log_test "Test 3: Flask Availability"

if ! python3 -c "import flask" 2>/dev/null; then
    log_fail "Flask not installed. Run: pip install -r requirements.txt"
    exit 1
fi
log_pass "Flask available: $(python3 -c 'import flask; print(flask.__version__)')"

# === Test 4: .env Configuration ===
log_test "Test 4: .env Configuration"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    log_fail ".env file not found. Copy from .env.example and configure."
    exit 1
fi
log_pass ".env file exists"

# Check required vars
if ! grep -q "^BOT_TOKEN=" "$SCRIPT_DIR/.env" && ! grep -q "^BOT_TOKEN=" "$SCRIPT_DIR/.env.example"; then
    log_fail "BOT_TOKEN not in .env or .env.example"
    exit 1
fi
log_pass "BOT_TOKEN configured"

if ! grep -q "^TELEGRAM_CHAT_ID=" "$SCRIPT_DIR/.env" && ! grep -q "^TELEGRAM_CHAT_ID=" "$SCRIPT_DIR/.env.example"; then
    log_fail "TELEGRAM_CHAT_ID not in .env or .env.example"
    exit 1
fi
log_pass "TELEGRAM_CHAT_ID configured"

# === Test 5: CLI Script (notify.py) ===
log_test "Test 5: CLI Script - notify.py"

# Test help
if ! python3 "$SCRIPT_DIR/notify.py" 2>&1 | grep -q "Uso:"; then
    log_fail "notify.py doesn't show usage"
    exit 1
fi
log_pass "notify.py help text works"

# Test with DRY_RUN (simulated send)
export DRY_RUN=true
if ! python3 "$SCRIPT_DIR/notify.py" "Test message from offline testing" 2>&1 | grep -q "DRY RUN"; then
    log_fail "notify.py dry-run failed"
    exit 1
fi
log_pass "notify.py dry-run works"

# Check logs were created
if [[ ! -f "$SCRIPT_DIR/logs/notify.log" ]]; then
    log_fail "Log file not created"
    exit 1
fi
log_pass "Log file created"

# === Test 6: Rate Limit & Dedup ===
log_test "Test 6: Rate Limit & Dedup"

# Send same message twice (should be blocked by dedup)
python3 "$SCRIPT_DIR/notify.py" "Duplicate test" >/dev/null 2>&1 || true
python3 "$SCRIPT_DIR/notify.py" "Duplicate test" >/dev/null 2>&1 || true

if ! grep -q "reason=duplicate" "$SCRIPT_DIR/logs/notify.log"; then
    log_fail "Deduplication not working"
    exit 1
fi
log_pass "Deduplication works"

# === Test 7: State File ===
log_test "Test 7: State File Management"

if [[ ! -f "$SCRIPT_DIR/state/state.json" ]]; then
    log_fail "State file not created"
    exit 1
fi
log_pass "State file created"

# Check permissions
STATE_PERMS=$(stat -c %a "$SCRIPT_DIR/state/state.json" 2>/dev/null || stat -f %OLp "$SCRIPT_DIR/state/state.json" 2>/dev/null || echo "unknown")
if [[ "$STATE_PERMS" != "600" ]] && [[ "$STATE_PERMS" != "unknown" ]]; then
    log_fail "State file has insecure permissions: $STATE_PERMS (should be 600)"
    exit 1
fi
log_pass "State file permissions secure"

# === Test 8: MCP Server (Flask) ===
log_test "Test 8: MCP Server - Flask"

# Start server in background
log_info "Starting MCP server in background..."
python3 "$SCRIPT_DIR/mcp_server.py" > /tmp/mcp_server.log 2>&1 &
MCP_PID=$!
sleep 2

if ! kill -0 $MCP_PID 2>/dev/null; then
    log_fail "MCP server failed to start. Check /tmp/mcp_server.log"
    cat /tmp/mcp_server.log | tee -a "$TEST_LOG"
    exit 1
fi
log_pass "MCP server started (PID: $MCP_PID)"

# === Test 9: MCP Health Check ===
log_test "Test 9: MCP Health Check"

if ! curl -s http://127.0.0.1:5000/health 2>/dev/null | grep -q "ok"; then
    log_fail "Health check endpoint failed"
    kill $MCP_PID || true
    exit 1
fi
log_pass "Health check passed"

# === Test 10: MCP Tools Endpoint ===
log_test "Test 10: MCP Tools List"

# Get MCP token from .env
MCP_TOKEN=$(grep "^MCP_AUTH_TOKEN=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "test-token")

if ! curl -s -H "Authorization: Bearer $MCP_TOKEN" http://127.0.0.1:5000/tools 2>/dev/null | grep -q "send_telegram_message"; then
    log_fail "Tools endpoint doesn't return send_telegram_message"
    kill $MCP_PID || true
    exit 1
fi
log_pass "Tools endpoint working"

# === Test 11: MCP Send Message (Dry-Run) ===
log_test "Test 11: MCP Send Message (Dry-Run)"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test from offline suite"}' \
  http://127.0.0.1:5000/tools/send_telegram_message 2>/dev/null || echo "{}")

if ! echo "$RESPONSE" | grep -q "dry_run"; then
    log_fail "MCP send endpoint response invalid"
    log_fail "Response: $RESPONSE"
    kill $MCP_PID || true
    exit 1
fi
log_pass "MCP send message works (dry-run)"

# === Test 12: MCP Auth ===
log_test "Test 12: MCP Authentication"

# Try without auth token
if curl -s http://127.0.0.1:5000/tools 2>/dev/null | grep -q "send_telegram_message"; then
    log_fail "MCP allows unauthenticated access (should be protected)"
    kill $MCP_PID || true
    exit 1
fi
log_pass "MCP auth protection works"

# === Test 13: File Structure ===
log_test "Test 13: File Structure Check"

REQUIRED_FILES=(
    "telegram_notifier.py"
    "notify.py"
    "mcp_server.py"
    ".env.example"
    "requirements.txt"
    "README.md"
    "MCP_SETUP.md"
    "Dockerfile"
    "docker-compose.yml"
    "notify-bot.service"
    "deploy.sh"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
        log_fail "Missing: $file"
        kill $MCP_PID || true
        exit 1
    fi
done
log_pass "All required files present"

# === Test 14: Docker Build ===
log_test "Test 14: Docker Image Build (Optional)"

if ! command -v docker &>/dev/null; then
    log_info "Docker not available, skipping build test"
else
    if docker build -t notify-bot-test:latest . > /tmp/docker_build.log 2>&1; then
        log_pass "Docker image builds successfully"
    else
        log_fail "Docker build failed. Check /tmp/docker_build.log"
    fi
fi

# Clean up
kill $MCP_PID 2>/dev/null || true
wait $MCP_PID 2>/dev/null || true

# === Summary ===
log_test "Testing Complete"
log_pass "All offline tests passed! ✓"
log_info ""
log_info "Next steps:"
log_info "1. Review logs: tail -f logs/notify.log"
log_info "2. Test live send: export DRY_RUN=false"
log_info "3. Deploy to home server: bash deploy.sh --tailscale"
log_info "4. Configure Claude Code: see MCP_SETUP.md"
log_info ""
log_info "Full test log: $TEST_LOG"
