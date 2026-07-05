#!/bin/bash
# =================================================================
#  OpenClaude Portable - Termux One-Liner Setup
#  Usage: curl -sSL https://raw.githubusercontent.com/techjarves/OpenClaude-Portable/main/termux-setup.sh | bash
# =================================================================
set -e

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
BOLD='\033[1m'; RESET='\033[0m'

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

# --- Request storage permission ---
echo -e "${YELLOW}[~] Requesting storage access...${RESET}"
termux-setup-storage 2>/dev/null || true

# --- Update packages ---
echo -e "${YELLOW}[~] Updating Termux packages...${RESET}"
pkg update -y -qq 2>/dev/null || pkg update -y
pkg upgrade -y -qq 2>/dev/null || pkg upgrade -y

# --- Install dependencies ---
echo -e "${YELLOW}[~] Installing Node.js and dependencies...${RESET}"
pkg install -y nodejs curl git -qq 2>/dev/null || pkg install -y nodejs curl git

echo -e "${GREEN}[OK] Dependencies installed!${RESET}"

# --- Clone repo if not already present ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/start.sh" ]; then
    echo -e "${YELLOW}[~] Cloning OpenClaude Portable...${RESET}"
    cd "$HOME"
    rm -rf OpenClaude-Portable
    git clone --depth=1 https://github.com/techjarves/OpenClaude-Portable.git
    cd OpenClaude-Portable
    chmod +x start.sh termux-setup.sh
    echo -e "${GREEN}[OK] Repository cloned!${RESET}"
else
    cd "$SCRIPT_DIR"
fi

echo ""
echo -e "${GREEN}=========================================================${RESET}"
echo -e "  ${BOLD}Setup complete! Run ./start.sh to launch.${RESET}"
echo -e "${GREEN}=========================================================${RESET}"
echo ""
echo -e "  ${CYAN}Quick start:${RESET} ./start.sh"
echo -e "  ${CYAN}One-liner (next time):${RESET} bash termux-setup.sh"
echo ""
