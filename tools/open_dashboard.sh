#!/bin/bash
# =================================================================
#  OpenClaude Portable - Dashboard (All Platforms)
# =================================================================

C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'
B='\033[1m'; N='\033[0m'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/engine"
DASHBOARD="$ROOT/dashboard/server.mjs"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')

# ── Termux Detection ────────────────────────────────────────
TERMUX=0
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then TERMUX=1; fi

if [ "$TERMUX" -eq 1 ]; then
    NODE=$(command -v node) || { echo -e "  ${R}[ERROR] Node.js not found. Run: pkg install nodejs${N}"; exit 1; }
else
    case "$OS" in darwin) P="darwin" ;; linux) P="linux" ;;
        *) echo -e "${R}[ERROR] Unsupported: $OS${N}"; exit 1 ;;
    esac
    A=""; case "$(uname -m)" in x86_64|amd64) A="x64" ;; arm64|aarch64) A="arm64" ;;
        *) echo -e "${R}[ERROR] Unsupported arch${N}"; exit 1 ;;
    esac
    NODE="$ENGINE/node-$P-$A/bin/node"
    [ ! -f "$NODE" ] && { echo -e "  ${R}[ERROR] Run start.sh first${N}"; exit 1; }
fi

export CLAUDE_CONFIG_DIR="$ROOT/data/openclaude"
export XDG_CONFIG_HOME="$ROOT/data/config"
mkdir -p "$CLAUDE_CONFIG_DIR" "$XDG_CONFIG_HOME"

echo ""
echo -e "${C}=========================================================${N}"
echo -e "  ${B}OpenClaude Portable - Dashboard${N}"
echo -e "${C}=========================================================${N}"
echo ""

[ ! -f "$DASHBOARD" ] && { echo -e "  ${R}[ERROR] Dashboard not found${N}"; exit 1; }

# ── Port Check ──────────────────────────────────────────────
port_busy() {
    if command -v lsof >/dev/null 2>&1; then lsof -i :3000 >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then ss -tlnp | grep -q ':3000 '
    else return 1
    fi
}

if port_busy; then
    echo -e "  ${Y}[!] Port 3000 already in use${N}"
    echo -e "  Open http://localhost:3000 in your browser"
    if command -v termux-open-url >/dev/null 2>&1; then termux-open-url "http://localhost:3000"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "http://localhost:3000"
    elif command -v open >/dev/null 2>&1; then open "http://localhost:3000"
    fi
    exit 0
fi

echo -e "  ${C}[~] Starting dashboard at ${B}http://localhost:3000${N}"
echo ""

if command -v termux-open-url >/dev/null 2>&1; then (sleep 2 && termux-open-url "http://localhost:3000") &
elif command -v xdg-open >/dev/null 2>&1; then (sleep 2 && xdg-open "http://localhost:3000") &
elif command -v open >/dev/null 2>&1; then (sleep 2 && open "http://localhost:3000") &
fi

exec "$NODE" "$DASHBOARD"
