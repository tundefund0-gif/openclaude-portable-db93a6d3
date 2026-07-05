#!/bin/bash
# =================================================================
#  OpenClaude Portable - Doctor (Diagnostics)
#  Checks all components and reports health status
# =================================================================

C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'
B='\033[1m'; N='\033[0m'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/engine"
DATA="$ROOT/data"
ENV_FILE="$DATA/ai_settings.env"

echo ""
echo -e "${C}=========================================================${N}"
echo -e "  ${B}OpenClaude Portable - Diagnostics${N}"
echo -e "${C}=========================================================${N}"
echo ""

# ── Detect Termux ───────────────────────────────────────────
TERMUX=0
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then TERMUX=1; fi

# ── Helper ──────────────────────────────────────────────────
check() {
    local label="$1" status="$2" detail="$3"
    local icon
    case "$status" in
        PASS) icon="${G}[PASS]${N}" ;;
        WARN) icon="${Y}[WARN]${N}" ;;
        FAIL) icon="${R}[FAIL]${N}" ;;
    esac
    printf "  %-32s %s  %s\n" "$label" "$icon" "$detail"
}

# ── 1. Platform ─────────────────────────────────────────────
echo -e "  ${B}── Platform ──${N}"
check "OS" "PASS" "$(uname -s) $(uname -m)"
if [ "$TERMUX" -eq 1 ]; then
    check "Termux" "PASS" "detected ($PREFIX)"
    REAL_HOME="$(dirname "$PREFIX")"
    if [ -d "$REAL_HOME/storage" ]; then
        check "Storage" "PASS" "linked"
    else
        check "Storage" "WARN" "not linked (run: termux-setup-storage)"
    fi
fi
echo ""

# ── 2. Node.js ─────────────────────────────────────────────
echo -e "  ${B}── Node.js ──${N}"
if [ "$TERMUX" -eq 1 ]; then
    NODE=$(command -v node || true)
    NPM=$(command -v npm || true)
else
    for d in "$ENGINE"/node-*/bin/node; do
        [ -f "$d" ] && NODE="$d" && break
    done
    NPM="${NODE%/*}/npm"
fi

if [ -n "$NODE" ] && "$NODE" --version >/dev/null 2>&1; then
    check "Node.js" "PASS" "$("$NODE" --version)"
else
    check "Node.js" "FAIL" "not found"
fi

if [ -n "$NPM" ] && "$NPM" --version >/dev/null 2>&1; then
    check "npm" "PASS" "$("$NPM" --version)"
else
    check "npm" "FAIL" "not found"
fi
echo ""

# ── 3. Engine ──────────────────────────────────────────────
echo -e "  ${B}── OpenClaude Engine ──${N}"
OC_DIR="$ENGINE/node_modules/@gitlawb/openclaude"
OC_BIN="$OC_DIR/bin/openclaude"
OC_CLI="$OC_DIR/dist/cli.mjs"

if [ -f "$OC_BIN" ] && [ -f "$OC_CLI" ]; then
    check "Engine installed" "PASS" "$OC_DIR"
    # Try to get version
    if [ -f "$OC_DIR/package.json" ]; then
        VER=$(grep '"version"' "$OC_DIR/package.json" | sed 's/.*: *"//;s/".*//' 2>/dev/null || echo "?")
        check "Engine version" "PASS" "$VER"
    fi
else
    check "Engine installed" "FAIL" "missing"
    if [ -d "$OC_DIR" ]; then
        check "Partial install" "WARN" "files incomplete - run start.sh to repair"
    fi
fi

if [ -f "$ENGINE/install.log" ]; then
    check "Install log" "PASS" "$ENGINE/install.log ($(wc -l < "$ENGINE/install.log") lines)"
fi

# Check npm cache
if [ -d "$DATA/npm-cache" ]; then
    check "npm cache" "PASS" "$DATA/npm-cache"
fi
echo ""

# ── 4. Config ──────────────────────────────────────────────
echo -e "  ${B}── Configuration ──${N}"
if [ -f "$ENV_FILE" ]; then
    check "Settings file" "PASS" "$ENV_FILE"
    PROVIDER=$(grep "^AI_PROVIDER=" "$ENV_FILE" | sed 's/.*=//' || echo "?")
    MODEL=$(grep "^AI_DISPLAY_MODEL=" "$ENV_FILE" | sed 's/.*=//' || echo "?")
    check "Provider" "PASS" "$PROVIDER"
    check "Model" "PASS" "$MODEL"
    # Check for required keys
    case "$PROVIDER" in
        openai)
            KEY=$(grep "^OPENAI_API_KEY=" "$ENV_FILE" | sed 's/.*=//' || true)
            if [ -n "$KEY" ] && [ "$KEY" != "not-needed" ]; then
                check "API Key" "PASS" "${KEY:0:6}****${KEY: -4}"
            elif [ "$KEY" = "not-needed" ]; then
                check "API Key" "PASS" "local provider"
            else
                check "API Key" "FAIL" "missing"
            fi ;;
        anthropic)
            KEY=$(grep "^ANTHROPIC_API_KEY=" "$ENV_FILE" | sed 's/.*=//' || true)
            [ -n "$KEY" ] && check "API Key" "PASS" "${KEY:0:6}****${KEY: -4}" || check "API Key" "FAIL" "missing" ;;
        gemini)
            KEY=$(grep "^GEMINI_API_KEY=" "$ENV_FILE" | sed 's/.*=//' || true)
            [ -n "$KEY" ] && check "API Key" "PASS" "${KEY:0:6}****${KEY: -4}" || check "API Key" "FAIL" "missing" ;;
    esac
else
    check "Settings file" "FAIL" "not found (run: ./start.sh to configure)"
fi
echo ""

# ── 5. Ollama ──────────────────────────────────────────────
echo -e "  ${B}── Ollama (Local AI) ──${N}"
OLLAMA=""
for f in "$DATA/ollama/ollama" "$DATA/ollama/ollama-linux"; do
    [ -x "$f" ] && OLLAMA="$f" && break
done
if [ -n "$OLLAMA" ]; then
    check "Binary" "PASS" "$OLLAMA"
    # Check for models
    MODELS_DIR="$DATA/ollama/data/manifests/registry.ollama.ai/library"
    if [ -d "$MODELS_DIR" ]; then
        COUNT=$(find "$MODELS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        check "Models" "PASS" "$COUNT model(s) downloaded"
    else
        check "Models" "WARN" "none downloaded (run option 5)"
    fi
else
    check "Binary" "WARN" "not installed (run option 5)"
fi
echo ""

# ── 6. Network ─────────────────────────────────────────────
echo -e "  ${B}── Network ──${N}"
if command -v curl >/dev/null 2>&1; then
    check "curl" "PASS" "available"
    if curl -sf --max-time 5 https://registry.npmjs.org >/dev/null 2>&1; then
        check "Internet" "PASS" "connected"
    else
        check "Internet" "WARN" "no connection (offline mode ok for Ollama)"
    fi
else
    check "curl" "FAIL" "not installed"
fi
echo ""

# ── Summary ─────────────────────────────────────────────────
echo -e "${C}=========================================================${N}"
echo -e "  ${B}Diagnostics Complete${N}"
echo -e "${C}=========================================================${N}"
echo ""
echo -e "  Report any issues at: https://github.com/tundefund0-gif/openclaude-portable-db93a6d3"
echo ""
