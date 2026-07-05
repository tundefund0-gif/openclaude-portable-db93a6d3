#!/bin/bash
# =================================================================
#  OpenClaude Portable - Termux Setup Script
#  Run directly after cloning:
#    git clone --depth=1 https://github.com/tundefund0-gif/openclaude-portable-db93a6d3.git ~/openclaude-portable
#    cd ~/openclaude-portable && bash termux-setup.sh
#
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

# --- Detect Termux ---
if [ -z "$PREFIX" ] || [ ! -d "$PREFIX" ]; then
    echo -e "${RED}[ERROR] This script must be run inside Termux on Android.${RESET}"
    exit 1
fi

# --- Request storage permission (optional, skip if already set up) ---
if [ ! -d "$HOME/storage" ]; then
    echo -e "${YELLOW}[~] Requesting storage access (5s timeout)...${RESET}"
    timeout 5 termux-setup-storage 2>/dev/null || echo -e "${DIM}    Skipped (not required for operation)${RESET}"
fi

# --- Update packages ---
echo -e "${YELLOW}[~] Updating Termux packages...${RESET}"
pkg update -y -qq 2>/dev/null || pkg update -y
pkg upgrade -y -qq 2>/dev/null || pkg upgrade -y

# --- Install dependencies ---
echo -e "${YELLOW}[~] Installing Node.js and dependencies...${RESET}"
pkg install -y nodejs curl git -qq 2>/dev/null || pkg install -y nodejs curl git

echo -e "${GREEN}[OK] Dependencies installed!${RESET}"

# --- Ensure we're in the repo directory ---
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
cd "$SCRIPT_DIR"
chmod +x start.sh tools/*.sh 2>/dev/null || true

echo ""
echo -e "${GREEN}=========================================================${RESET}"
echo -e "  ${BOLD}Setup complete! Run ./start.sh to launch.${RESET}"
echo -e "${GREEN}=========================================================${RESET}"
echo ""
echo -e "  ${CYAN}Quick start:${RESET} cd ~/openclaude-portable && ./start.sh"
echo -e "  ${CYAN}One-liner (next time):${RESET}"
echo -e "    git clone --depth=1 https://github.com/tundefund0-gif/openclaude-portable-db93a6d3.git ~/openclaude-portable && bash ~/openclaude-portable/termux-setup.sh"
echo ""
