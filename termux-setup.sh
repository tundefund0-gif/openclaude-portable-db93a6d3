#!/bin/bash
# =================================================================
#  OpenClaude Portable - Termux Full Setup v1.1.0
#  Installs everything needed to run AI coding on Android
#
#  One-liner:
#    git clone --depth=1 https://github.com/tundefund0-gif/openclaude-portable-db93a6d3.git ~/openclaude-portable && bash ~/openclaude-portable/termux-setup.sh
#
#  This script is idempotent - safe to re-run for updates.
# =================================================================
set -euo pipefail

C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'
B='\033[1m'; N='\033[0m'

# ── Help ────────────────────────────────────────────────────
if [ "$1" = "--help" ] || [ "$1" = "-h" ] 2>/dev/null; then
    echo ""
    echo "  OpenClaude Portable - Termux Setup"
    echo ""
    echo "  Usage: bash termux-setup.sh [OPTIONS]"
    echo ""
    echo "  Options:"
    echo "    --help, -h        Show this help"
    echo "    --skip-packages   Skip apt update/upgrade"
    echo "    --skip-storage    Skip termux-setup-storage"
    echo ""
    echo "  This script installs all dependencies and creates the 'openclaude' alias."
    echo "  It is idempotent - safe to re-run."
    echo ""
    exit 0
fi

SKIP_PKG=0; SKIP_STORAGE=0
for arg in "$@"; do
    [ "$arg" = "--skip-packages" ] && SKIP_PKG=1
    [ "$arg" = "--skip-storage" ] && SKIP_STORAGE=1
done

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
if [ ! -d "$REAL_HOME/storage" ] && [ "$SKIP_STORAGE" -eq 0 ]; then
    echo -e "  ${Y}[~] Setting up storage access (5s timeout)...${N}"
    timeout 5 termux-setup-storage 2>/dev/null || echo -e "  ${D}    Skipped (not required)${N}"
else
    echo -e "  ${D}[i] Storage already configured${N}"
fi

# ── Package Update ──────────────────────────────────────────
if [ "$SKIP_PKG" -eq 0 ]; then
    echo -e "  ${Y}[~] Updating Termux packages...${N}"
    pkg update -y -qq 2>/dev/null || pkg update -y
    pkg upgrade -y -qq 2>/dev/null || pkg upgrade -y
else
    echo -e "  ${D}[i] Skipping package update${N}"
fi

# ── Install Dependencies ────────────────────────────────────
echo -e "  ${Y}[~] Installing dependencies...${N}"
DEPS="nodejs curl git openssh zstd"
NEEDS_INSTALL=""
for dep in $DEPS; do
    if pkg list-installed 2>/dev/null | grep -q "^${dep}[[:space:]]"; then
        echo -e "  ${D}    $dep already installed${N}"
    else
        NEEDS_INSTALL="$NEEDS_INSTALL $dep"
    fi
done

if [ -n "$NEEDS_INSTALL" ]; then
    echo -e "  ${Y}    Installing:$NEEDS_INSTALL${N}"
    pkg install -y $NEEDS_INSTALL -qq 2>/dev/null || pkg install -y $NEEDS_INSTALL
else
    echo -e "  ${G}[OK] All dependencies already installed${N}"
fi

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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$SCRIPT_DIR/start.sh" "$SCRIPT_DIR/tools/"*.sh 2>/dev/null || true
echo -e "  ${G}[OK] Execute permissions set${N}"

# ── Create Convenience Alias ────────────────────────────────
BASHRC="$HOME/.bashrc"
ALIAS_CMD="alias openclaude='cd ${SCRIPT_DIR} && ./start.sh'"
if grep -q "alias openclaude=" "$BASHRC" 2>/dev/null; then
    # Update existing alias path if repo moved
    sed -i "s|alias openclaude='.*'|$ALIAS_CMD|" "$BASHRC"
    echo -e "  ${D}[i] 'openclaude' alias updated${N}"
else
    echo "" >> "$BASHRC"
    echo "# OpenClaude Portable" >> "$BASHRC"
    echo "$ALIAS_CMD" >> "$BASHRC"
    echo -e "  ${G}[OK] Added 'openclaude' alias to .bashrc${N}"
    echo -e "  ${D}    Run: source ~/.bashrc${N}"
fi

# ── Done ────────────────────────────────────────────────────
echo ""
echo -e "${G}=========================================================${N}"
echo -e "  ${B}Setup Complete!${N}"
echo -e "${G}=========================================================${N}"
echo ""
echo -e "  ${C}Launch:${N}  cd ${SCRIPT_DIR} && ./start.sh"
echo -e "  ${C}Alias:${N}   openclaude   (after: source ~/.bashrc)"
echo -e "  ${C}Update:${N}  cd ${SCRIPT_DIR} && git pull && bash termux-setup.sh"
echo ""
