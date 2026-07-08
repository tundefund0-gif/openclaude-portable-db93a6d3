#!/bin/bash
# =================================================================
#  OpenClaude Portable v1.1.0
#  Zero-footprint AI coding agent - macOS / Linux / Termux (Android)
# =================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'; D='\033[90m'
B='\033[1m'; N='\033[0m'

# ── Paths ───────────────────────────────────────────────────
ROOT="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$ROOT/engine"
DATA="$ROOT/data"
ENV_FILE="$DATA/ai_settings.env"
NPM_CACHE="$DATA/npm-cache"
INSTALL_LOG="$ENGINE/install.log"
OC_DIR="$ENGINE/node_modules/@gitlawb/openclaude"
OC_BIN="$OC_DIR/bin/openclaude"
OC_CLI="$OC_DIR/dist/cli.mjs"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# ── Detect Termux ───────────────────────────────────────────
TERMUX=0
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then TERMUX=1; fi

# ── Cleanup handler ─────────────────────────────────────────
cleanup() {
    echo -e "\n${D}[~] Shutting down...${N}"
    if [ -n "${OLLAMA_PID:-}" ]; then
        kill "$OLLAMA_PID" 2>/dev/null || true
        wait "$OLLAMA_PID" 2>/dev/null || true
    fi
    exit 0
}
TRAP=1; trap cleanup SIGINT SIGTERM; trap 'TRAP=0' EXIT

# ── Helpers ─────────────────────────────────────────────────
say() { echo -e "$1"; }
ok()  { say "  ${G}[OK]${N} $1"; }
warn() { say "  ${Y}[!]${N} $1"; }
fail() { say "  ${R}[ERROR]${N} $1"; exit 1; }
info() { say "  ${D}[i]${N} $1"; }

spin() {
    local pid=$1 msg="$2" max=${3:-300}
    local s=0 sp='/-\|'
    while kill -0 "$pid" 2>/dev/null && [ $s -lt $max ]; do
        printf "\r  ${D}${msg}... ${sp:s++%4:1} ${s}s${N}"
        sleep 1
    done
    printf "\r"
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        return 1
    fi
    wait "$pid"
    return $?
}

# ── Node.js Setup ───────────────────────────────────────────
setup_node() {
    if [ "$TERMUX" -eq 1 ]; then
        NODE=$(command -v node) || fail "Node.js not found. Run: pkg install nodejs"
        NPM=$(command -v npm) || fail "npm not found"
        ok "Node.js $($NODE --version) (system)"
    else
        local VER="22.14.0"
        local DL="$ENGINE/node-dl.log"
        case "$OS" in darwin) P="darwin"; E="tar.gz" ;; linux) P="linux"; E="tar.xz" ;;
            *) fail "Unsupported OS: $OS" ;;
        esac
        case "$ARCH" in x86_64|amd64) A="x64" ;; arm64|aarch64) A="arm64" ;;
            *) fail "Unsupported arch: $ARCH" ;;
        esac
        local DIR="$ENGINE/node-$P-$A"
        NODE="$DIR/bin/node"
        NPM="$DIR/bin/npm"
        mkdir -p "$ENGINE"
        if [ ! -f "$NODE" ]; then
            local TAR="$ENGINE/node.$E"
            local URL="https://nodejs.org/dist/v${VER}/node-v${VER}-${P}-${A}.${E}"
            local FALL="https://r2.nodejs.org/dist/v${VER}/node-v${VER}-${P}-${A}.${E}"
            info "Downloading Node.js v${VER}..."
            rm -f "$TAR" "$DL"
            curl -fL --retry 3 --connect-timeout 20 "$URL" -o "$TAR" >> "$DL" 2>&1 ||
            curl -fL --retry 3 --connect-timeout 20 "$FALL" -o "$TAR" >> "$DL" 2>&1 ||
                fail "Download failed. See $DL"
            info "Extracting..."
            rm -rf "$DIR" && mkdir -p "$DIR"
            tar -xf "$TAR" -C "$DIR" --strip-components=1 || fail "Extract failed"
            rm -f "$TAR"
            ok "Node.js $VER installed"
        fi
        export PATH="$DIR/bin:$PATH"
    fi
}

# ── Engine Install ──────────────────────────────────────────
engine_ok() { [ -f "$OC_BIN" ] && [ -f "$OC_CLI" ]; }

install_engine() {
    local action="$1"
    info "${action} OpenClaude Engine..."
    cd "$ENGINE"
    mkdir -p "$NPM_CACHE"
    : > "$INSTALL_LOG"
    local TIMEOUT=300
    NPM_CONFIG_CACHE="$NPM_CACHE" "$NPM" install @gitlawb/openclaude@latest \
        --no-audit --no-fund --loglevel=warn --no-bin-links --cache "$NPM_CACHE" \
        >> "$INSTALL_LOG" 2>&1 &
    local npm_pid=$!
    spin $npm_pid "${action} engine" "$TIMEOUT"
    local st=$?
    if [ $st -eq 0 ] && engine_ok; then
        ok "Engine ${action,,}ed!"
    elif [ $st -ne 0 ]; then
        if kill -0 "$npm_pid" 2>/dev/null; then
            warn "npm timed out after ${TIMEOUT}s — killing..."
            kill "$npm_pid" 2>/dev/null || true
        fi
        fail "Install failed (npm exit $st). See $INSTALL_LOG"
    else
        fail "Engine incomplete. Run again to repair."
    fi
}

# ── Config Load / Save ──────────────────────────────────────
load_config() {
    if [ -f "$ENV_FILE" ]; then
        local c; c=$(tr -d '\r' < "$ENV_FILE" 2>/dev/null || true)
        if [[ "$c" == *"AI_PROVIDER="* ]]; then
            while IFS='=' read -r k v; do
                [[ "$k" =~ ^#.* ]] && continue; [ -z "$k" ] && continue
                export "$k=$v"
            done <<< "$c"
            return 0
        fi
    fi
    return 1
}

save_env() { echo "$1" > "$ENV_FILE"; }
mask_key() { echo "${1:0:6}****${1: -4}"; }

verify_key() {
    local p="$1" k="$2"
    info "Verifying API key..."
    case "$p" in
        openrouter) curl -sf -H "Authorization: Bearer $k" https://openrouter.ai/api/v1/auth/key >/dev/null 2>&1 ;;
        gemini)     curl -sf "https://generativelanguage.googleapis.com/v1beta/models?key=$k" >/dev/null 2>&1 ;;
        anthropic)  curl -sf -H "x-api-key: $k" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/models >/dev/null 2>&1 ;;
        nvidia)     curl -sf -H "Authorization: Bearer $k" https://integrate.api.nvidia.com/v1/models >/dev/null 2>&1 ;;
        deepseek)   curl -sf -H "Authorization: Bearer $k" https://api.deepseek.com/models >/dev/null 2>&1 ;;
        openai)     curl -sf -H "Authorization: Bearer $k" https://api.openai.com/v1/models >/dev/null 2>&1 ;;
        lmstudio)   curl -sf -H "Authorization: Bearer lm-studio" "${k%/}/models" >/dev/null 2>&1 ;;
        custom|ollama) return 0 ;;
        *) return 1 ;;
    esac
    return $?
}

pick_model() {
    local models="$1" prompt="$2"
    local i=1; declare -a arr
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        say "  ${C}${i})${N} $m"
        arr[$i]="$m"; i=$((i+1))
    done <<< "$models"
    say "  ${C}${i})${N} ${D}Custom...${N}"
    read -p "  ${prompt} " sel
    [ -z "$sel" ] && sel=1
    if [ "$sel" = "$i" ]; then read -p "  Model name: " USER_MODEL
    else USER_MODEL="${arr[$sel]}"; fi
    [ -z "$USER_MODEL" ] && USER_MODEL="${arr[1]}"
}

fetch_models() { curl -sf -H "Authorization: Bearer ${2:-x}" "${1}" 2>/dev/null || true; }

# ── Provider Setups ─────────────────────────────────────────
setup_provider() {
    while true; do
        say ""
        say "${C}=========================================================${N}"
        say "  ${B}AI PROVIDER${N}"
        say "${C}=========================================================${N}"
        say "  ${C}1)${N} OpenRouter    ${D}- 200+ free/paid models${N}  ${G}[REC]${N}"
        say "  ${C}2)${N} NVIDIA NIM   ${D}- Free GPU tier${N}         ${G}[REC]${N}"
        say "  ${C}3)${N} DeepSeek     ${D}- OpenAI-compatible API${N}"
        say "  ${C}4)${N} Gemini       ${D}- Google AI${N}"
        say "  ${C}5)${N} Claude       ${D}- Anthropic API${N}"
        say "  ${C}6)${N} OpenAI       ${D}- GPT / Codex API${N}"
        say "  ${C}7)${N} Ollama       ${D}- Local offline${N}"
        say "  ${C}8)${N} LM Studio    ${D}- Local server${N}"
        say "  ${C}9)${N} Custom API   ${D}- Any OpenAI-compatible${N}"
        read -p "  Select (1-9): " s
        case "$s" in 1) setup_openrouter; break ;; 2) setup_nvidia; break ;;
            3) setup_deepseek; break ;; 4) setup_gemini; break ;; 5) setup_claude; break ;;
            6) setup_openai; break ;; 7) setup_ollama; break ;; 8) setup_lmstudio; break ;;
            9) setup_custom_openai; break ;; *) say "  ${R}Invalid${N}" ;;
        esac
    done
}

setup_openrouter() {
    read -p "  OpenRouter API Key: " k; [ -z "$k" ] && setup_openrouter && return
    verify_key openrouter "$k" || { fail "Invalid key"; }
    say "  ${C}1)${N} Free  2)${N} Paid"; read -p "  Tier: " t
    json=$(fetch_models "https://openrouter.ai/api/v1/models" "x" 2>/dev/null)
    if [ "$t" = "1" ]; then
        models=$(echo "$json" | grep -Eo '"id"[^"]*:free"' | sed 's/"id" *: *"//;s/"//g' | head -20)
    else
        models=$(echo "$json" | grep -Eo '"id"[^"]*"' | sed 's/"id" *: *"//;s/"//g' | grep -v ':free$' | head -20)
    fi
    [ -z "$models" ] && read -p "  Model: " USER_MODEL || pick_model "$models" "Model:"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=https://openrouter.ai/api/v1
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
    ok "Provider set to OpenRouter ($USER_MODEL)"
}

setup_nvidia() {
    read -p "  NVIDIA API Key: " k; [ -z "$k" ] && setup_nvidia && return
    verify_key nvidia "$k" || fail "Invalid key"
    CURATED="qwen/qwen2.5-coder-32b-instruct meta/llama-3.3-70b-instruct meta/llama-3.1-405b-instruct deepseek-ai/deepseek-v3.1-terminus"
    LIVE=$(fetch_models "https://integrate.api.nvidia.com/v1/models" "$k" 2>/dev/null | grep -Eo '"id"[^"]*"' | sed 's/"id" *: *"//;s/"//g' | head -40)
    models=""; for m in $CURATED; do models="${models}${m}"$'\n'; done; models="${models}${LIVE}"
    pick_model "$models" "Model:"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=https://integrate.api.nvidia.com/v1
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}
CLAUDE_CODE_AGENT_LIST_IN_MESSAGES=false
CLAUDE_CODE_SIMPLE=1"
    ok "Provider set to NVIDIA NIM ($USER_MODEL)"
}

setup_deepseek() {
    read -p "  DeepSeek API Key: " k; [ -z "$k" ] && setup_deepseek && return
    verify_key deepseek "$k" || fail "Invalid key"
    models=$(fetch_models "https://api.deepseek.com/models" "$k" 2>/dev/null | grep -Eo '"id"[^"]*"' | sed 's/"id" *: *"//;s/"//g')
    [ -z "$models" ] && models="deepseek-v4-flash"$'\n'"deepseek-v4-pro"
    pick_model "$models" "Model [Enter=1]:"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=https://api.deepseek.com
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
    ok "Provider set to DeepSeek ($USER_MODEL)"
}

setup_gemini() {
    read -p "  Gemini API Key: " k; k=$(echo "$k" | tr -d ' \r')
    [ -z "$k" ] && setup_gemini && return
    verify_key gemini "$k" || fail "Invalid key"
    models=$(curl -sf "https://generativelanguage.googleapis.com/v1alpha/models?key=$k" 2>/dev/null | grep -Eo '"name"[^"]*"' | sed 's/"name" *: *"models\///;s/"//g' | grep -vE 'vision|embedding|banana' | head -40)
    [ -z "$models" ] && read -p "  Model: " USER_MODEL || pick_model "$models" "Model [Enter=1]:"
    save_env "AI_PROVIDER=gemini
CLAUDE_CODE_USE_GEMINI=1
GEMINI_API_KEY=$k
GEMINI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
    ok "Provider set to Gemini ($USER_MODEL)"
}

setup_claude() {
    read -p "  Anthropic API Key: " k; [ -z "$k" ] && setup_claude && return
    verify_key anthropic "$k" || fail "Invalid key"
    read -p "  Model [claude-3-7-sonnet-20250219]: " USER_MODEL
    [ -z "$USER_MODEL" ] && USER_MODEL="claude-3-7-sonnet-20250219"
    save_env "AI_PROVIDER=anthropic
ANTHROPIC_API_KEY=$k
AI_DISPLAY_MODEL=${USER_MODEL}"
    ok "Provider set to Claude ($USER_MODEL)"
}

setup_openai() {
    read -p "  OpenAI API Key: " k; [ -z "$k" ] && setup_openai && return
    verify_key openai "$k" || fail "Invalid key"
    read -p "  Model [gpt-4o]: " USER_MODEL; [ -z "$USER_MODEL" ] && USER_MODEL="gpt-4o"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
    ok "Provider set to OpenAI ($USER_MODEL)"
}

setup_ollama() {
    local bin="$DATA/ollama/ollama"
    [ ! -f "$bin" ] && bin="$DATA/ollama/ollama-linux"
    [ ! -x "$bin" ] && warn "Ollama not found. Run option 5 in menu to install." && return
    export OLLAMA_MODELS="$DATA/ollama/data"
    "$bin" serve >/dev/null 2>&1 & local pid=$!; sleep 2
    models=$("$bin" list 2>/dev/null | awk 'NR>1 {print $1}')
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
    [ -z "$models" ] && warn "No models found. Run option 5." && return
    pick_model "$models" "Model:"
    save_env "AI_PROVIDER=ollama
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=ollama
OPENAI_BASE_URL=http://localhost:11434/v1
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
    ok "Provider set to Ollama ($USER_MODEL)"
}

setup_lmstudio() {
    say "  Start LM Studio, load a model, enable Developer > Local Server"
    read -p "  URL [http://localhost:1234/v1]: " b; [ -z "$b" ] && b="http://localhost:1234/v1"
    b="${b%/}"
    if ! curl -sf -H "Authorization: Bearer lm-studio" "${b}/models" >/dev/null 2>&1; then
        warn "Cannot reach LM Studio at $b"
        read -p "  Continue anyway? (y/N): " c; [[ ! "$c" =~ ^[Yy]$ ]] && setup_lmstudio && return
    fi
    models=$(curl -sf -H "Authorization: Bearer lm-studio" "${b}/models" 2>/dev/null | grep -Eo '"id"[^"]*"' | sed 's/"id" *: *"//;s/"//g')
    [ -z "$models" ] && read -p "  Model: " USER_MODEL || pick_model "$models" "Model:"
    [ -z "$USER_MODEL" ] && read -p "  Model: " USER_MODEL
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=lm-studio
OPENAI_BASE_URL=${b}
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
    ok "Provider set to LM Studio ($USER_MODEL)"
}

setup_custom_openai() {
    read -p "  Base URL (e.g. https://api.example.com/v1): " b; [ -z "$b" ] && setup_custom_openai && return
    b="${b%/}"; read -p "  API Key (Enter=none): " k; [ -z "$k" ] && k="not-needed"
    if ! curl -sf -H "Authorization: Bearer $k" "${b}/models" >/dev/null 2>&1; then
        warn "Cannot verify ${b}/models"
        read -p "  Continue? (y/N): " c; [[ ! "$c" =~ ^[Yy]$ ]] && setup_custom_openai && return
    fi
    models=$(curl -sf -H "Authorization: Bearer $k" "${b}/models" 2>/dev/null | grep -Eo '"id"[^"]*"' | sed 's/"id" *: *"//;s/"//g')
    [ -z "$models" ] && read -p "  Model: " USER_MODEL || pick_model "$models" "Model [Enter=manual]:"
    [ -z "$USER_MODEL" ] && read -p "  Model: " USER_MODEL
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=${b}
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
    ok "Provider configured ($USER_MODEL)"
}

# ── Provider Name ───────────────────────────────────────────
provider_name() {
    local n="$AI_PROVIDER"
    case "$AI_PROVIDER" in
        openai) case "${OPENAI_BASE_URL:-}" in *openrouter*) n="OpenRouter" ;;
            *nvidia*) n="NVIDIA NIM" ;; *deepseek*) n="DeepSeek" ;;
            *openai*) n="OpenAI" ;; *11434*) n="Ollama" ;;
            *1234*) n="LM Studio" ;; *) n="Custom API" ;; esac ;;
        gemini) n="Google Gemini" ;; anthropic) n="Anthropic Claude" ;; ollama) n="Ollama" ;;
    esac
    echo "$n"
}

# ═════════════════════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════════════════════

# ── Phase 1: Bootstrap ─────────────────────────────────────
setup_node

# ── Phase 2: Engine ────────────────────────────────────────
if ! engine_ok; then
    [ -d "$OC_DIR" ] && rm -rf "$OC_DIR"
    install_engine "Installing"
fi

# ── Phase 3: Portable Environment ──────────────────────────
export CLAUDE_CONFIG_DIR="$DATA/openclaude"
export HOME="$DATA/home"
export USERPROFILE="$HOME"
export APPDATA="$DATA/app_data"
export LOCALAPPDATA="$DATA/local_app_data"
export XDG_CONFIG_HOME="$DATA/config"
export XDG_DATA_HOME="$DATA/app_data"
export XDG_CACHE_HOME="$DATA/cache"
export PATH="$ENGINE/node_modules/.bin:$PATH"
mkdir -p "$CLAUDE_CONFIG_DIR" "$HOME" "$APPDATA" "$LOCALAPPDATA" \
       "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$DATA"

# ── Banner ──────────────────────────────────────────────────
say ""
say "${C}    ____            __        __    __        ___    ____${N}"
say "${C}   / __ \\____  ____/ /_____ _/ /_  / /__     /   |  /  _/${N}"
say "${C}  / /_/ / __ \\/ __/ __/ __ \`/ __ \\/ / _ \\   / /| |  / /  ${N}"
say "${C} / ____/ /_/ / / / /_/ /_/ / /_/ / /  __/  / ___ |_/ /   ${N}"
say "${C}/_/    \\____/_/  \\__/\\__,_/_.___/_/\\___/  /_/  |_/___/   ${N}"
say ""
say "${C}=========================================================${N}"
say "  ${B}OpenClaude Portable${N}"
[ "$TERMUX" -eq 1 ] && say "  ${G}[Termux Android Mode]${N}"
say "${C}=========================================================${N}"
say ""

# ── Flags ───────────────────────────────────────────────────
OFFLINE=0; QUICK=0; RESET=0
for arg in "$@"; do
    case "$arg" in
        --offline) OFFLINE=1 ;;
        --quick) QUICK=1 ;;
        --reset-config) RESET=1 ;;
        --doctor|--diagnose) exec bash "$ROOT/tools/opencode-doctor.sh" ;;
        --update) exec bash "$ROOT/tools/opencode-update.sh" ;;
        --version|-v)
            echo "OpenClaude Portable v1.4.0"
            echo "Engine: @gitlawb/openclaude"
            exit 0 ;;
        --help|-h)
            echo ""
            echo "  OpenClaude Portable v1.4.0 - Zero-footprint AI coding agent"
            echo ""
            echo "  Usage: ./start.sh [OPTIONS]"
            echo ""
            echo "  Options:"
            echo "    --offline         Skip update checks"
            echo "    --reset-config    Re-run provider setup"
            echo "    --doctor/--diagnose Run diagnostics"
            echo "    --update          Pull latest + reinstall engine"
            echo "    --version, -v     Show version"
            echo "    --help, -h        Show this help"
            echo ""
            echo "  Always runs in Limitless mode (no approval prompts)."
            echo ""
            exit 0 ;;
    esac
done

# ── Update Check ────────────────────────────────────────────
if [ $OFFLINE -eq 1 ]; then
    info "Offline mode - skipped update check"
else
    info "Checking for engine updates..."
    cd "$ENGINE"
    if "$NPM" outdated @gitlawb/openclaude 2>/dev/null | grep -q openclaude; then
        install_engine "Upgrading"
    fi
    ok "Engine is current"
fi

# ── Config ──────────────────────────────────────────────────
if [ $RESET -eq 1 ]; then
    rm -f "$ENV_FILE"
    warn "Config reset. Setting up new provider..."
fi
if ! load_config; then
    setup_provider
    say ""
    ok "Settings saved"
    load_config
fi

# ── Final Validation ────────────────────────────────────────
[ -z "${AI_PROVIDER:-}" ] && fail "No provider configured"
case "$AI_PROVIDER" in
    openai) [ -z "${OPENAI_API_KEY:-}" ] && fail "Missing API key" ;;
    anthropic) [ -z "${ANTHROPIC_API_KEY:-}" ] && fail "Missing API key" ;;
    gemini) [ -z "${GEMINI_API_KEY:-}" ] && fail "Missing API key" ;;
    ollama) : ;;
esac
[ "$AI_PROVIDER" = "openai" ] && [ -n "${OPENAI_BASE_URL:-}" ] && [ -z "${OPENAI_API_FORMAT:-}" ] && export OPENAI_API_FORMAT="chat_completions"
export CLAUDE_CODE_PROVIDER_PROFILE_ENV_APPLIED=1
export CLAUDE_CODE_PROVIDER_PROFILE_ENV_APPLIED_ID=portable-env

PNAME=$(provider_name)
say "${C}=========================================================${N}"
say "  ${B}Ready${N}"
say "${C}=========================================================${N}"
say "  Provider: ${G}${PNAME}${N}"
say "  Model   : ${G}${AI_DISPLAY_MODEL:-${OPENAI_MODEL:-${GEMINI_MODEL:-${ANTHROPIC_MODEL:-?}}}}${N}"
say "  Mode    : ${D}Zero-footprint portable${N}"
say "${C}=========================================================${N}"
say ""

# ── Menu ────────────────────────────────────────────────────
CMD_ARGS="--dangerously-skip-permissions"
if [ $QUICK -eq 0 ]; then
    while true; do
        say "  ${B}Action (Limitless):${N}"
        say "  ${C}1)${N} ${R}Launch AI${N}         ${D}(auto 10s)${N}"
        say "  ${D}────────────────${N}"
        say "  ${C}2)${N} Dashboard     ${D}(web UI)${N}"
        say "  ${C}3)${N} Change Provider"
        say "  ${C}4)${N} Install Ollama ${D}(local models)${N}"
        say ""
        LAUNCH=""
        for i in 9 8 7 6 5 4 3 2 1 0; do
            printf "\r  Select (1-4) [auto ${i}]: "
            if [ "$TERMUX" -eq 1 ]; then read -t 1 LAUNCH 2>/dev/null || true
            else read -t 1 -n 1 LAUNCH 2>/dev/null || true; fi
            [ -n "$LAUNCH" ] && break
        done
        [ -z "$LAUNCH" ] && LAUNCH="1"
        say ""
        case "$LAUNCH" in
            1) break ;;
            2) trap - EXIT; exec bash "$ROOT/tools/open_dashboard.sh" ;;
            3) trap - EXIT; exec bash "$ROOT/tools/change_provider.sh" ;;
            4) trap - EXIT; exec bash "$ROOT/tools/setup_local_models.sh" ;;
            *) say "  ${R}Invalid${N}" ;;
        esac
    done
fi

# ── Ollama Launch ───────────────────────────────────────────
if [ "$AI_PROVIDER" = "ollama" ]; then
    local bin="$DATA/ollama/ollama"
    [ ! -f "$bin" ] && bin="$DATA/ollama/ollama-linux"
    if [ -x "$bin" ]; then
        info "Starting Ollama..."
        export OLLAMA_MODELS="$DATA/ollama/data"
        "$bin" serve >/dev/null 2>&1 &
        OLLAMA_PID=$!; sleep 3
        if kill -0 "$OLLAMA_PID" 2>/dev/null; then
            ok "Ollama running (PID $OLLAMA_PID)"
        else
            warn "Ollama may have failed to start"
        fi
    fi
fi

# ── Launch ──────────────────────────────────────────────────
PROV_ARGS=()
case "$AI_PROVIDER" in
    anthropic) PROV_ARGS=(--provider anthropic) ;;
    gemini)    PROV_ARGS=(--provider gemini) ;;
    ollama)    PROV_ARGS=(--provider ollama) ;;
    openai)    [[ "${OPENAI_BASE_URL:-}" == *nvidia* ]] && PROV_ARGS=(--provider nvidia-nim) ;;
esac
MODEL_ARGS=()
[ -n "${OPENAI_MODEL:-}" ] && MODEL_ARGS=(--model "$OPENAI_MODEL")
[ -n "${GEMINI_MODEL:-}" ] && MODEL_ARGS=(--model "$GEMINI_MODEL")
[ -n "${ANTHROPIC_MODEL:-}" ] && MODEL_ARGS=(--model "$ANTHROPIC_MODEL")

cd "$ENGINE"
if [ -f "$OC_BIN" ]; then
    info "Starting AI Engine..."
    exec "$NODE" "$OC_BIN" --setting-sources local "${PROV_ARGS[@]}" "${MODEL_ARGS[@]}" $CMD_ARGS
else
    fail "Engine missing. Run ./start.sh again to repair."
fi
