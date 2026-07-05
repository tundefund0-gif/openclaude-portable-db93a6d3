#!/bin/bash
# =================================================================
#  OpenClaude Portable - Termux Setup
#  One-liner:
#    git clone --depth=1 https://github.com/tundefund0-gif/openclaude-portable-db93a6d3.git ~/openclaude-portable && bash ~/openclaude-portable/termux-setup.sh
# =================================================================
set -e

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
DIM='\033[90m'; BOLD='\033[1m'; RESET='\033[0m'

echo ""
echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${BOLD}OpenClaude Portable - Termux Installer${RESET}"
echo -e "${CYAN}=========================================================${RESET}"
echo ""

# --- Verify Termux ---
if [ -z "$PREFIX" ] || [ ! -d "$PREFIX" ]; then
    echo -e "${RED}[ERROR] Must run inside Termux on Android${RESET}"
    exit 1
fi

# --- Update packages ---
echo -e "${YELLOW}[~] Updating packages...${RESET}"
pkg update -y -qq 2>/dev/null || pkg update -y
pkg upgrade -y -qq 2>/dev/null || pkg upgrade -y

# --- Install dependencies ---
echo -e "${YELLOW}[~] Installing Node.js + dependencies...${RESET}"
pkg install -y nodejs curl git -qq 2>/dev/null || pkg install -y nodejs curl git
echo -e "${GREEN}[OK] Dependencies installed${RESET}"

# --- Set permissions ---
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
cd "$SCRIPT_DIR"
chmod +x start.sh tools/*.sh 2>/dev/null || true

echo ""
echo -e "${GREEN}=========================================================${RESET}"
echo -e "  ${BOLD}Ready! Run: cd ${SCRIPT_DIR} && ./start.sh${RESET}"
echo -e "${GREEN}=========================================================${RESET}"
echo ""
echo -e "  ${CYAN}Tip:${RESET} Run 'termux-setup-storage' for shared file access (optional)"
echo ""
