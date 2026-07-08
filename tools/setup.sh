#!/bin/bash
# =================================================================
#  OpenClaude Portable - Full Environment Setup
#  One-shot: checks deps, installs Node.js, installs engine,
#  configures provider, sets permissions.
# =================================================================
set -euo pipefail

C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'
B='\033[1m'; N='\033[0m'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/engine"
DATA="$ROOT/data"

if [ "$1" = "--help" ] || [ "$1" = "-h" ] 2>/dev/null; then
    echo ""
    echo "  OpenClaude Portable - Full Environment Setup"
    echo ""
    echo "  Usage: bash tools/setup.sh [OPTIONS]"
    echo ""
    echo "  Sets up everything needed to run OpenClaude Portable."
    echo "  Checks Node.js, installs engine, configures provider."
    echo ""
    exit 0
fi

echo ""
echo -e "${C}=========================================================${N}"
echo -e "  ${B}OpenClaude Portable - Full Setup${N}"
echo -e "${C}=========================================================${N}"
echo ""

# ── Step 1: Check dependencies ──────────────────────────────
echo -e "  ${Y}[1/5]${N} Checking dependencies..."
MISSING=""
for cmd in curl git; do
    if ! command -v "$cmd" &>/dev/null; then MISSING="$MISSING $cmd"; fi
done
if [ -n "$MISSING" ]; then
    echo -e "  ${R}Missing:$MISSING${N}"
    echo -e "  ${D}Install: apt install$MISSING (Linux) or pkg install$MISSING (Termux)${N}"
    exit 1
fi
echo -e "  ${G}[OK]${N} curl, git available"

# ── Step 2: Node.js ─────────────────────────────────────────
echo -e "  ${Y}[2/5]${N} Setting up Node.js..."
NODE=""; NPM=""
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then
    NODE=$(command -v node) || { echo -e "  ${R}[ERROR] Install: pkg install nodejs${N}"; exit 1; }
    NPM=$(command -v npm)
    echo -e "  ${G}[OK]${N} Node.js $($NODE --version) (system)"
else
    VER="22.14.0"
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case "$OS" in darwin) P="darwin" ;; linux) P="linux" ;;
        *) echo -e "${R}[ERROR] Unsupported OS: $OS${N}"; exit 1 ;;
    esac
    case "$ARCH" in x86_64|amd64) A="x64" ;; arm64|aarch64) A="arm64" ;;
        *) echo -e "${R}[ERROR] Unsupported arch: $ARCH${N}"; exit 1 ;;
    esac
    DIR="$ENGINE/node-$P-$A"
    NODE="$DIR/bin/node"
    NPM="$DIR/bin/npm"
    if [ ! -f "$NODE" ]; then
        mkdir -p "$ENGINE"
        TAR="$ENGINE/node.tar.${P == 'darwin' ? 'gz' : 'xz'}"
        URL="https://nodejs.org/dist/v${VER}/node-v${VER}-${P}-${A}.tar.xz"
        FALL="https://r2.nodejs.org/dist/v${VER}/node-v${VER}-${P}-${A}.tar.xz"
        echo -e "  ${D}    Downloading Node.js v${VER}...${N}"
        curl -fL --retry 3 --connect-timeout 20 "$URL" -o "$TAR" 2>/dev/null ||
        curl -fL --retry 3 --connect-timeout 20 "$FALL" -o "$TAR" 2>/dev/null ||
            { echo -e "  ${R}[ERROR] Download failed${N}"; exit 1; }
        rm -rf "$DIR" && mkdir -p "$DIR"
        tar -xf "$TAR" -C "$DIR" --strip-components=1 || { echo -e "  ${R}[ERROR] Extract failed${N}"; exit 1; }
        rm -f "$TAR"
    fi
    echo -e "  ${G}[OK]${N} Node.js $($NODE --version)"
fi

# ── Step 3: Install engine ──────────────────────────────────
echo -e "  ${Y}[3/5]${N} Installing OpenClaude Engine..."
mkdir -p "$DATA/npm-cache" "$ENGINE"
cd "$ENGINE"
NPM_CONFIG_CACHE="$DATA/npm-cache" "$NPM" install @gitlawb/openclaude@latest \
    --no-audit --no-fund --loglevel=warn --no-bin-links --cache "$DATA/npm-cache" 2>&1 | sed 's/^/  /'
OC_DIR="$ENGINE/node_modules/@gitlawb/openclaude"
OC_BIN="$OC_DIR/bin/openclaude"
if [ ! -f "$OC_BIN" ]; then echo -e "  ${R}[ERROR] Engine install failed${N}"; exit 1; fi
echo -e "  ${G}[OK]${N} Engine installed"

# ── Step 4: Permissions ─────────────────────────────────────
echo -e "  ${Y}[4/5]${N} Setting permissions..."
chmod +x "$ROOT/start.sh" "$ROOT/tools/"*.sh 2>/dev/null || true
echo -e "  ${G}[OK]${N} Permissions set"

# ── Step 5: Run start.sh to configure provider ──────────────
echo -e "  ${Y}[5/5]${N} Launching provider setup..."
echo ""
echo -e "${C}=========================================================${N}"
echo -e "  ${B}Setup complete! Running provider configuration...${N}"
echo -e "${C}=========================================================${N}"
echo ""
cd "$ROOT"
exec bash "$ROOT/start.sh" --reset-config
