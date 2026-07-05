#!/bin/bash
# =================================================================
#  OpenClaude Portable - Termux One-Liner Setup
#  Usage: curl -sSL https://raw.githubusercontent.com/tundefund0-gif/openclaude-portable-db93a6d3/main/termux-setup.sh | bash
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
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
REPO_URL="https://github.com/tundefund0-gif/openclaude-portable-db93a6d3.git"
CLONE_DIR="openclaude-portable"
if [ -f "$SCRIPT_DIR/start.sh" ] && [ "$SCRIPT_DIR" != "/dev/fd" ] && [ "$SCRIPT_DIR" != "/proc" ] && [[ "$SCRIPT_DIR" != /proc/* ]]; then
    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}[~] Cloning OpenClaude Portable...${RESET}"
    cd "$HOME"
    # Clean up any stale directories from previous runs
    rm -rf "$CLONE_DIR" "OpenClaude-Portable" "openclaude-portable-db93a6d3"
    git clone --depth=1 "$REPO_URL" "$CLONE_DIR"
    cd "$CLONE_DIR"
    chmod +x start.sh
    echo -e "${GREEN}[OK] Repository cloned!${RESET}"
fi

echo ""
echo -e "${GREEN}=========================================================${RESET}"
echo -e "  ${BOLD}Setup complete! Run ./start.sh to launch.${RESET}"
echo -e "${GREEN}=========================================================${RESET}"
echo ""
echo -e "  ${CYAN}Quick start:${RESET} cd ~/openclaude-portable && ./start.sh"
echo -e "  ${CYAN}One-liner (next time):${RESET} bash ~/openclaude-portable/termux-setup.sh"
echo ""
