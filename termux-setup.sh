#!/bin/bash
# =================================================================
#  OpenClaude Portable - Termux Full Setup
#  Installs everything needed to run AI coding on Android
#
#  One-liner:
#    git clone --depth=1 https://github.com/tundefund0-gif/openclaude-portable-db93a6d3.git ~/openclaude-portable && bash ~/openclaude-portable/termux-setup.sh
# =================================================================
set -euo pipefail

C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'
B='\033[1m'; N='\033[0m'

banner() {
    echo ""
    echo -e "${C}=========================================================${N}"
    echo -e "  ${B}OpenClaude Portable - Termux Installer${N}"
    echo -e "${C}=========================================================${N}"
    echo ""
}
banner

# ── Verify Termux ───────────────────────────────────────────
if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
    echo -e "${R}[ERROR] Must run inside Termux on Android${N}"
    echo -e "  Install Termux from F-Droid: https://f-droid.org/packages/com.termux/"
    exit 1
fi

# ── Check Termux Version ───────────────────────────────────
echo -e "  ${D}[i] Termux root: $PREFIX${N}"
echo -e "  ${D}[i] Arch: $(uname -m)${N}"
echo -e "  ${D}[i] Android: $(getprop ro.build.version.release 2>/dev/null || echo '?')${N}"

# ── Storage Setup ───────────────────────────────────────────
REAL_HOME="$(dirname "$PREFIX")"
if [ ! -d "$REAL_HOME/storage" ]; then
    echo -e "  ${Y}[~] Setting up storage access (5s)...${N}"
    timeout 5 termux-setup-storage 2>/dev/null || echo -e "  ${D}    Skipped (not required)${N}"
fi

# ── Package Update ──────────────────────────────────────────
echo -e "  ${Y}[~] Updating Termux packages...${N}"
pkg update -y -qq 2>/dev/null || pkg update -y
pkg upgrade -y -qq 2>/dev/null || pkg upgrade -y

# ── Install Dependencies ────────────────────────────────────
echo -e "  ${Y}[~] Installing dependencies...${N}"
DEPS="nodejs curl git openssh zstd"
for dep in $DEPS; do
    if pkg list-installed 2>/dev/null | grep -q "^$dep "; then
        echo -e "  ${D}    $dep already installed${N}"
    else
        echo -e "  ${Y}    Installing $dep...${N}"
        pkg install -y "$dep" -qq 2>/dev/null || pkg install -y "$dep"
    fi
done
echo -e "  ${G}[OK] Dependencies installed${N}"

# ── Verify Node.js ──────────────────────────────────────────
NODE=$(command -v node || true)
NPM=$(command -v npm || true)
if [ -z "$NODE" ] || [ -z "$NPM" ]; then
    echo -e "  ${R}[ERROR] Node.js installation failed${N}"
    exit 1
fi
echo -e "  ${G}[OK] Node.js $($NODE --version)${N}"
echo -e "  ${G}[OK] npm $($NPM --version)${N}"

# ── Ensure Permissions ──────────────────────────────────────
cd "$(dirname "$0")"
chmod +x start.sh tools/*.sh 2>/dev/null || true

# ── Create Convenience Alias ────────────────────────────────
BASHRC="$HOME/.bashrc"
ALIAS_CMD="alias openclaude='cd ~/openclaude-portable && ./start.sh'"
if ! grep -q "alias openclaude=" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# OpenClaude Portable" >> "$BASHRC"
    echo "$ALIAS_CMD" >> "$BASHRC"
    echo -e "  ${G}[OK] Added 'openclaude' alias to .bashrc${N}"
    echo -e "  ${D}    Run: source ~/.bashrc${N}"
fi

# ── Done ────────────────────────────────────────────────────
DIR="$(pwd)"
echo ""
echo -e "${G}=========================================================${N}"
echo -e "  ${B}Setup Complete!${N}"
echo -e "${G}=========================================================${N}"
echo ""
echo -e "  ${C}Launch:${N}  cd $DIR && ./start.sh"
echo -e "  ${C}Alias:${N}   openclaude   (after: source ~/.bashrc)"
echo -e "  ${C}Update:${N}  cd $DIR && git pull"
echo ""
