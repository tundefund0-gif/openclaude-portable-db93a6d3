#!/bin/bash
# =================================================================
#  OpenClaude Portable - Self Updater
#  Pulls latest version from GitHub and reinstalls engine
# =================================================================

set -euo pipefail

C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'
B='\033[1m'; N='\033[0m'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/engine"
DATA="$ROOT/data"
ENV_FILE="$DATA/ai_settings.env"
BACKUP="$DATA/backups"

echo ""
echo -e "${C}=========================================================${N}"
echo -e "  ${B}OpenClaude Portable - Updater${N}"
echo -e "${C}=========================================================${N}"
echo ""

# ── Check git ───────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    echo -e "  ${R}[ERROR] git not found${N}"
    echo -e "  ${D}Install: pkg install git (Termux) or apt install git (Linux)${N}"
    exit 1
fi

# ── Backup config ───────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
    mkdir -p "$BACKUP"
    cp "$ENV_FILE" "$BACKUP/ai_settings.env.bak.$(date +%Y%m%d_%H%M%S)"
    echo -e "  ${G}[OK] Config backed up${N}"
fi

# ── Git pull ────────────────────────────────────────────────
echo -e "  ${Y}[~] Fetching latest version...${N}"
cd "$ROOT"
if git diff --quiet HEAD 2>/dev/null; then
    git pull --rebase 2>&1 || {
        echo -e "  ${R}[ERROR] Git pull failed${N}"
        echo -e "  ${D}Try: cd $ROOT && git stash && git pull${N}"
        exit 1
    }
    echo -e "  ${G}[OK] Updated to latest commit${N}"
else
    echo -e "  ${Y}[!] Local changes detected - stashing...${N}"
    git stash
    git pull --rebase
    echo -e "  ${Y}[!] Local changes stashed. Run: git stash pop${N}"
fi

# ── Reinstall engine ────────────────────────────────────────
echo -e "  ${Y}[~] Reinstalling OpenClaude Engine...${N}"
rm -rf "$ENGINE/node_modules/@gitlawb/openclaude" 2>/dev/null || true

# Find node/npm
NODE=""
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then
    NODE=$(command -v node)
    NPM=$(command -v npm)
else
    for d in "$ENGINE"/node-*/bin/node; do
        [ -f "$d" ] && NODE="$d" && break
    done
    NPM="${NODE%/*}/npm"
fi

if [ -z "$NODE" ] || [ -z "$NPM" ]; then
    echo -e "  ${R}[ERROR] Node.js not found. Run start.sh first.${N}"
    exit 1
fi

cd "$ENGINE"
mkdir -p "$DATA/npm-cache"
export NPM_CONFIG_CACHE="$DATA/npm-cache"

"$NPM" install @gitlawb/openclaude@latest --no-audit --no-fund --loglevel=warn --no-bin-links --cache "$DATA/npm-cache" 2>&1 | sed 's/^/  /'
echo -e "  ${G}[OK] Engine reinstalled${N}"

# ── Ensure permissions ──────────────────────────────────────
chmod +x "$ROOT/start.sh" "$ROOT/termux-setup.sh" "$ROOT/tools/"*.sh 2>/dev/null || true

# ── Done ────────────────────────────────────────────────────
echo ""
echo -e "${G}=========================================================${N}"
echo -e "  ${B}Update Complete!${N}"
echo -e "${G}=========================================================${N}"
echo ""
echo -e "  Run ${C}./start.sh${N} to launch"
echo -e "  Run ${C}bash tools/opencode-doctor.sh${N} to verify"
echo ""
