#!/bin/bash
# =================================================================
#  OpenClaude Portable - Dashboard (macOS/Linux/Termux)
# =================================================================

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
DIM='\033[90m'; BOLD='\033[1m'; RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_DIR="$ROOT_DIR/engine"
DASHBOARD="$ROOT_DIR/dashboard/server.mjs"

OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# ─── Termux Detection ──────────────────────────────────────
TERMUX_MODE=0
if [ -n "$PREFIX" ] && [ -d "$PREFIX" ]; then
    TERMUX_MODE=1
elif [ "$OS_NAME" = "linux" ] && echo "$HOME" | grep -q "com.termux"; then
    TERMUX_MODE=1
fi

if [ "$TERMUX_MODE" -eq 1 ]; then
    NODE="$(command -v node || true)"
    [ -z "$NODE" ] && { echo -e "  ${RED}[ERROR] Node.js not found! Run: pkg install nodejs${RESET}"; exit 1; }
else
    if [ "$OS_NAME" = "darwin" ]; then
        PLATFORM="darwin"
    elif [ "$OS_NAME" = "linux" ]; then
        PLATFORM="linux"
    else
        echo -e "${RED}[ERROR] Unsupported OS: $OS_NAME${RESET}"; exit 1
    fi
    case "$ARCH" in x86_64|amd64) NODE_ARCH="x64" ;; arm64|aarch64) NODE_ARCH="arm64" ;;
        *) echo -e "${RED}[ERROR] Unsupported: $ARCH${RESET}"; exit 1 ;;
    esac
    NODE="$ENGINE_DIR/node-$PLATFORM-$NODE_ARCH/bin/node"
    [ ! -f "$NODE" ] && { echo -e "  ${RED}[ERROR] Node.js not found. Run start.sh first.${RESET}"; exit 1; }
fi

# Portable data
DATA_DIR="$ROOT_DIR/data"
export CLAUDE_CONFIG_DIR="$DATA_DIR/openclaude"
export XDG_CONFIG_HOME="$DATA_DIR/config"
export XDG_DATA_HOME="$DATA_DIR/app_data"
mkdir -p "$CLAUDE_CONFIG_DIR" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

echo ""
echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${BOLD}OpenClaude Portable - Dashboard${RESET}"
echo -e "${CYAN}=========================================================${RESET}"
echo ""

[ ! -f "$DASHBOARD" ] && { echo -e "  ${RED}[ERROR] Dashboard not found!${RESET}"; exit 1; }

# Check port 3000
port_used() {
    if command -v lsof >/dev/null 2>&1; then lsof -i :3000 >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then ss -tlnp | grep -q ':3000 '
    else return 1
    fi
}

if port_used; then
    echo -e "  ${YELLOW}[WARN] Port 3000 already in use${RESET}"
    echo -e "  ${CYAN}1)${RESET} Open browser  2)${RESET} Cancel"
    read -p "  Select: " c
    if [ "$c" = "1" ]; then
        if command -v termux-open-url >/dev/null 2>&1; then termux-open-url "http://localhost:3000"
        elif command -v xdg-open >/dev/null 2>&1; then xdg-open "http://localhost:3000"
        elif command -v open >/dev/null 2>&1; then open "http://localhost:3000"
        fi
        echo -e "  ${GREEN}[OK] Browser opened${RESET}"
    fi
    exit 0
fi

echo -e "  ${CYAN}[~] Starting dashboard at ${BOLD}http://localhost:3000${RESET}"
echo ""

# Open browser in background
if command -v termux-open-url >/dev/null 2>&1; then
    (sleep 2 && termux-open-url "http://localhost:3000") &
elif command -v xdg-open >/dev/null 2>&1; then
    (sleep 2 && xdg-open "http://localhost:3000") &
elif command -v open >/dev/null 2>&1; then
    (sleep 2 && open "http://localhost:3000") &
fi

echo -e "  ${GREEN}[OK] Press Ctrl+C to stop${RESET}"
"$NODE" "$DASHBOARD"
