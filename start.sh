#!/bin/bash
# =================================================================
#  OpenClaude Portable - Start AI (macOS/Linux/Termux)
#  Zero-footprint AI coding agent - runs from any folder
# =================================================================

set -e
# --- Colors ---
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
DIM='\033[90m'; BOLD='\033[1m'; RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
ENGINE_DIR="$ROOT_DIR/engine"
DATA_DIR="$ROOT_DIR/data"
ENV_FILE="$DATA_DIR/ai_settings.env"
NPM_CACHE_DIR="$DATA_DIR/npm-cache"
NPM_INSTALL_LOG="$ENGINE_DIR/openclaude-engine-install.log"
OPENCLAUDE_DIR="$ENGINE_DIR/node_modules/@gitlawb/openclaude"
OC_BIN="$OPENCLAUDE_DIR/bin/openclaude"
OC_CLI="$OPENCLAUDE_DIR/dist/cli.mjs"

OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# ─── Termux Detection ──────────────────────────────────────
TERMUX_MODE=0
if [ -n "$PREFIX" ] && [ -d "$PREFIX" ]; then
    TERMUX_MODE=1
elif [ "$OS_NAME" = "linux" ] && echo "$HOME" | grep -q "com.termux"; then
    TERMUX_MODE=1
fi

# ─── Platform / Node setup ─────────────────────────────────
if [ "$TERMUX_MODE" -eq 1 ]; then
    NODE_BIN="$(command -v node || true)"
    NPM_BIN="$(command -v npm || true)"
    NPX_BIN="$(command -v npx || true)"
    if [ -z "$NODE_BIN" ]; then
        echo -e "${RED}[ERROR] Node.js not found! Run: pkg install nodejs${RESET}"
        exit 1
    fi
    echo -e "${GREEN}[OK] Termux - using system Node.js $($NODE_BIN --version)${RESET}"
    mkdir -p "$ENGINE_DIR"
else
    # macOS/Linux - download bundled Node if missing
    NODE_VERSION="22.14.0"
    NODE_DOWNLOAD_LOG="$ENGINE_DIR/node-download.log"

    if [ "$OS_NAME" = "darwin" ]; then
        PLATFORM="darwin"; EXT="tar.gz"
    elif [ "$OS_NAME" = "linux" ]; then
        PLATFORM="linux"; EXT="tar.xz"
    else
        echo -e "${RED}[ERROR] Unsupported OS: $OS_NAME${RESET}"; exit 1
    fi

    case "$ARCH" in x86_64|amd64) NODE_ARCH="x64" ;; arm64|aarch64) NODE_ARCH="arm64" ;;
        *) echo -e "${RED}[ERROR] Unsupported arch: $ARCH${RESET}"; exit 1 ;;
    esac

    NODE_DIR="$ENGINE_DIR/node-$PLATFORM-$NODE_ARCH"
    NODE_BIN="$NODE_DIR/bin/node"
    NPM_BIN="$NODE_DIR/bin/npm"
    NPX_BIN="$NODE_DIR/bin/npx"
    mkdir -p "$ENGINE_DIR"

    if [ ! -f "$NODE_BIN" ]; then
        echo -e "${YELLOW}[~] Downloading Node.js v${NODE_VERSION} for $PLATFORM-$NODE_ARCH...${RESET}"
        URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${PLATFORM}-${NODE_ARCH}.${EXT}"
        FALLBACK="https://r2.nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${PLATFORM}-${NODE_ARCH}.${EXT}"
        TAR="$ENGINE_DIR/node.${EXT}"
        rm -f "$TAR" "$NODE_DOWNLOAD_LOG"
        if ! curl -fL --retry 3 --connect-timeout 20 "$URL" -o "$TAR" >> "$NODE_DOWNLOAD_LOG" 2>&1; then
            echo -e "${YELLOW}[WARN] Primary mirror failed, trying fallback...${RESET}"
            curl -fL --retry 3 --connect-timeout 20 "$FALLBACK" -o "$TAR" >> "$NODE_DOWNLOAD_LOG" 2>&1 || {
                echo -e "${RED}[ERROR] Failed to download Node.js. See $NODE_DOWNLOAD_LOG${RESET}"
                exit 1
            }
        fi
        echo -e "${YELLOW}[~] Extracting Node.js...${RESET}"
        rm -rf "$NODE_DIR" && mkdir -p "$NODE_DIR"
        tar -xf "$TAR" -C "$NODE_DIR" --strip-components=1
        rm -f "$TAR"
    fi
    export PATH="$NODE_DIR/bin:$PATH"
fi

# ─── Install / Verify Engine ───────────────────────────────
engine_ready() { [ -f "$OC_BIN" ] && [ -f "$OC_CLI" ]; }

install_engine() {
    local action="$1"
    echo -e "${YELLOW}[~] ${action} OpenClaude Engine...${RESET}"
    echo -e "${DIM}    Log: $NPM_INSTALL_LOG${RESET}"
    cd "$ENGINE_DIR"
    mkdir -p "$NPM_CACHE_DIR"
    : > "$NPM_INSTALL_LOG"

    # Run npm install in foreground with simple spinner
    NPM_CONFIG_CACHE="$NPM_CACHE_DIR" "$NPM_BIN" install @gitlawb/openclaude@latest \
        --no-audit --no-fund --loglevel=warn --no-bin-links --cache "$NPM_CACHE_DIR" \
        >> "$NPM_INSTALL_LOG" 2>&1 &
    local pid=$!
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        echo -ne "\r${DIM}    Installing... ${elapsed}s${RESET}  "
        sleep 5; elapsed=$((elapsed + 5))
    done
    wait "$pid"
    local st=$?
    echo ""
    [ $st -ne 0 ] && {
        echo -e "${RED}[ERROR] Engine install failed (npm exit $st).${RESET}"
        echo -e "${DIM}        Check log: $NPM_INSTALL_LOG${RESET}"
        exit 1
    }
    engine_ready || {
        echo -e "${RED}[ERROR] Engine install incomplete.${RESET}"
        exit 1
    }
    echo -e "${GREEN}[OK] Engine ${action,,}ed!${RESET}"
}

if ! engine_ready; then
    [ -d "$OPENCLAUDE_DIR" ] && rm -rf "$OPENCLAUDE_DIR"
    install_engine "Installing"
fi

# ─── Portable Environment ──────────────────────────────────
export CLAUDE_CONFIG_DIR="$DATA_DIR/openclaude"
export HOME="$DATA_DIR/home"
export USERPROFILE="$HOME"
export APPDATA="$DATA_DIR/app_data"
export LOCALAPPDATA="$DATA_DIR/local_app_data"
export XDG_CONFIG_HOME="$DATA_DIR/config"
export XDG_DATA_HOME="$DATA_DIR/app_data"
export XDG_CACHE_HOME="$DATA_DIR/cache"
mkdir -p "$CLAUDE_CONFIG_DIR" "$HOME" "$APPDATA" "$LOCALAPPDATA" \
       "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$DATA_DIR"

# ─── Banner ────────────────────────────────────────────────
echo ""
echo -e "${CYAN}    ____            __        __    __        ___    ____${RESET}"
echo -e "${CYAN}   / __ \\____  ____/ /_____ _/ /_  / /__     /   |  /  _/${RESET}"
echo -e "${CYAN}  / /_/ / __ \\/ __/ __/ __ \`/ __ \\/ / _ \\   / /| |  / /  ${RESET}"
echo -e "${CYAN} / ____/ /_/ / / / /_/ /_/ / /_/ / /  __/  / ___ |_/ /   ${RESET}"
echo -e "${CYAN}/_/    \\____/_/  \\__/\\__,_/_.___/_/\\___/  /_/  |_/___/   ${RESET}"
echo ""
echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${BOLD}OpenClaude Portable - Multi-Platform AI Agent${RESET}"
if [ "$TERMUX_MODE" -eq 1 ]; then
    echo -e "  ${GREEN}Termux (Android) Mode${RESET}"
fi
echo -e "${CYAN}=========================================================${RESET}"
echo ""

# ─── Termux storage hint ───────────────────────────────────
if [ "$TERMUX_MODE" -eq 1 ]; then
    TERMUX_REAL_HOME="$(dirname "$PREFIX")"
    [ ! -d "$TERMUX_REAL_HOME/storage" ] && \
        echo -e "  ${DIM}[i] Optional: run 'termux-setup-storage' for shared file access${RESET}"
fi

# ─── Parse Flags ───────────────────────────────────────────
SKIP_UPDATE=0; QUICK_MODE=0
for arg in "$@"; do
    [ "$arg" = "--offline" ] && SKIP_UPDATE=1
    [ "$arg" = "--quick" ] && QUICK_MODE=1
done

# ─── Engine Update Check ───────────────────────────────────
if [ $SKIP_UPDATE -eq 1 ]; then
    echo -e "  ${DIM}[~] Offline mode - skipping update check${RESET}"
else
    echo -e "  ${YELLOW}[~] Checking for updates...${RESET}"
    cd "$ENGINE_DIR"
    if "$NPM_BIN" outdated @gitlawb/openclaude 2>/dev/null | grep -q openclaude; then
        install_engine "Upgrading"
    else
        echo -e "  ${GREEN}[OK] Engine is up to date!${RESET}"
    fi
fi
echo ""

# ─── Load / Setup Provider ─────────────────────────────────
goto_loaded=0
if [ -f "$ENV_FILE" ]; then
    ENV_CONTENT="$(tr -d '\r' < "$ENV_FILE" 2>/dev/null || true)"
    if [[ "$ENV_CONTENT" == *"AI_PROVIDER="* ]]; then
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^#.* ]] && continue; [ -z "$key" ] && continue
            export "$key=$value"
        done <<< "$ENV_CONTENT"
        goto_loaded=1
    fi
fi

# ─── Provider Functions ─────────────────────────────────────
save_env() { echo "$1" > "$ENV_FILE"; }

mask_key() { echo "${1:0:6}****${1: -4}"; }

verify_key() {
    local p="$1" k="$2"
    echo -e "  ${YELLOW}[~] Verifying API Key...${RESET}"
    case "$p" in
        openrouter) curl -sf -H "Authorization: Bearer $k" https://openrouter.ai/api/v1/auth/key >/dev/null 2>&1 ;;
        gemini)     curl -sf "https://generativelanguage.googleapis.com/v1beta/models?key=$k" >/dev/null 2>&1 ;;
        anthropic)  curl -sf -H "x-api-key: $k" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/models >/dev/null 2>&1 ;;
        nvidia)     curl -sf -H "Authorization: Bearer $k" https://integrate.api.nvidia.com/v1/models >/dev/null 2>&1 ;;
        deepseek)   curl -sf -H "Authorization: Bearer $k" https://api.deepseek.com/models >/dev/null 2>&1 ;;
        openai)     curl -sf -H "Authorization: Bearer $k" https://api.openai.com/v1/models >/dev/null 2>&1 ;;
        lmstudio)   curl -sf -H "Authorization: Bearer lm-studio" "${k%/}/models" >/dev/null 2>&1 ;;
        custom)     return 0 ;;
    esac
}

fetch_models_json() {
    local url="$1" key="$2"
    curl -sf -H "Authorization: Bearer $key" "$url" 2>/dev/null
}

pick_model() {
    local models="$1" prompt="$2"
    local i=1; declare -a arr
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        echo -e "  ${CYAN}${i})${RESET} $m"
        arr[$i]="$m"; i=$((i+1))
    done <<< "$models"
    echo -e "  ${CYAN}${i})${RESET} ${DIM}Custom model...${RESET}"
    echo ""
    read -p "  $prompt " sel
    [ -z "$sel" ] && sel=1
    if [ "$sel" = "$i" ]; then
        read -p "  Enter custom model string: " USER_MODEL
    else
        USER_MODEL="${arr[$sel]}"
    fi
    [ -z "$USER_MODEL" ] && USER_MODEL="${arr[1]}"
}

setup_provider() {
    echo -e "${CYAN}=========================================================${RESET}"
    echo -e "  ${BOLD}AI PROVIDER SELECTION${RESET}"
    echo -e "${CYAN}=========================================================${RESET}"
    echo ""
    echo -e "  ${CYAN}1)${RESET} ${BOLD}OpenRouter${RESET}   ${DIM}- 200+ Free/Paid models${RESET}  ${GREEN}[REC]${RESET}"
    echo -e "  ${CYAN}2)${RESET} ${BOLD}NVIDIA NIM${RESET}   ${DIM}- Free GPU tier${RESET}         ${GREEN}[REC]${RESET}"
    echo -e "  ${CYAN}3)${RESET} ${BOLD}DeepSeek${RESET}     ${DIM}- OpenAI-compatible API${RESET}"
    echo -e "  ${CYAN}4)${RESET} ${BOLD}Gemini${RESET}       ${DIM}- Google AI API${RESET}"
    echo -e "  ${CYAN}5)${RESET} ${BOLD}Claude${RESET}       ${DIM}- Anthropic API${RESET}"
    echo -e "  ${CYAN}6)${RESET} ${BOLD}OpenAI${RESET}       ${DIM}- GPT / Codex API${RESET}"
    echo -e "  ${CYAN}7)${RESET} ${BOLD}Ollama${RESET}       ${DIM}- Local offline AI${RESET}"
    echo -e "  ${CYAN}8)${RESET} ${BOLD}LM Studio${RESET}    ${DIM}- Local server${RESET}"
    echo -e "  ${CYAN}9)${RESET} ${BOLD}Custom API${RESET}    ${DIM}- Any OpenAI-compatible${RESET}"
    echo ""
    read -p "  Select (1-9): " s; echo ""
    case "$s" in
        1) setup_openrouter ;; 2) setup_nvidia ;; 3) setup_deepseek ;;
        4) setup_gemini ;; 5) setup_claude ;; 6) setup_openai ;;
        7) setup_ollama ;; 8) setup_lmstudio ;; 9) setup_custom_openai ;;
        *) echo -e "  ${RED}Invalid${RESET}"; setup_provider ;;
    esac
}

setup_openrouter() {
    read -p "  OpenRouter API Key: " k
    [ -z "$k" ] && setup_openrouter && return
    verify_key openrouter "$k" || { echo -e "  ${RED}Invalid key${RESET}"; setup_openrouter; return; }
    echo -e "  ${CYAN}1)${RESET} Free  2)${RESET} Paid"
    read -p "  Tier: " t
    json=$(fetch_models_json "https://openrouter.ai/api/v1/models" "x")
    if [ "$t" = "1" ]; then
        models=$(echo "$json" | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*:free"' | sed 's/"id" *: *"//;s/"//g' | head -20)
    else
        models=$(echo "$json" | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"id" *: *"//;s/"//g' | grep -v ':free$' | head -20)
    fi
    [ -z "$models" ] && read -p "  Enter model: " USER_MODEL || pick_model "$models" "Choose model:"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=https://openrouter.ai/api/v1
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_nvidia() {
    read -p "  NVIDIA API Key: " k; [ -z "$k" ] && setup_nvidia && return
    verify_key nvidia "$k" || { echo -e "  ${RED}Invalid key${RESET}"; setup_nvidia; return; }
    CURATED="qwen/qwen2.5-coder-32b-instruct meta/llama-3.3-70b-instruct meta/llama-3.1-405b-instruct deepseek-ai/deepseek-v3.1-terminus"
    LIVE=$(fetch_models_json "https://integrate.api.nvidia.com/v1/models" "$k" 2>/dev/null | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"id" *: *"//;s/"//g' | head -40)
    models=""; for m in $CURATED; do models="${models}${m}"$'\n'; done; models="${models}${LIVE}"
    pick_model "$models" "Choose model:"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=https://integrate.api.nvidia.com/v1
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}
CLAUDE_CODE_AGENT_LIST_IN_MESSAGES=false
CLAUDE_CODE_SIMPLE=1"
}

setup_deepseek() {
    read -p "  DeepSeek API Key: " k; [ -z "$k" ] && setup_deepseek && return
    verify_key deepseek "$k" || { echo -e "  ${RED}Invalid key${RESET}"; setup_deepseek; return; }
    models=$(fetch_models_json "https://api.deepseek.com/models" "$k" 2>/dev/null | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"id" *: *"//;s/"//g')
    [ -z "$models" ] && models="deepseek-v4-flash"$'\n'"deepseek-v4-pro"
    pick_model "$models" "Choose model [Enter for 1]:"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=https://api.deepseek.com
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_gemini() {
    read -p "  Gemini API Key: " k; k=$(echo "$k" | tr -d ' \r')
    [ -z "$k" ] && setup_gemini && return
    verify_key gemini "$k" || { echo -e "  ${RED}Invalid key${RESET}"; setup_gemini; return; }
    models=$(curl -sf "https://generativelanguage.googleapis.com/v1alpha/models?key=$k" 2>/dev/null | grep -Eo '"name"[[:space:]]*:[[:space:]]*"models/gemini-[^"]*"' | sed 's/"name" *: *"models\///;s/"//g' | grep -vE 'vision|embedding|banana|lyria|robot|research|computer' | head -40)
    [ -z "$models" ] && read -p "  Enter model: " USER_MODEL || pick_model "$models" "Choose model [Enter for 1]:"
    save_env "AI_PROVIDER=gemini
CLAUDE_CODE_USE_GEMINI=1
GEMINI_API_KEY=$k
GEMINI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_claude() {
    read -p "  Anthropic API Key: " k; [ -z "$k" ] && setup_claude && return
    verify_key anthropic "$k" || { echo -e "  ${RED}Invalid key${RESET}"; setup_claude; return; }
    read -p "  Model [claude-3-7-sonnet-20250219]: " USER_MODEL
    [ -z "$USER_MODEL" ] && USER_MODEL="claude-3-7-sonnet-20250219"
    save_env "AI_PROVIDER=anthropic
ANTHROPIC_API_KEY=$k
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_openai() {
    read -p "  OpenAI API Key: " k; [ -z "$k" ] && setup_openai && return
    verify_key openai "$k" || { echo -e "  ${RED}Invalid key${RESET}"; setup_openai; return; }
    read -p "  Model [gpt-4o]: " USER_MODEL; [ -z "$USER_MODEL" ] && USER_MODEL="gpt-4o"
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_ollama() {
    OLLAMA_BIN="$DATA_DIR/ollama/ollama"
    [ ! -f "$OLLAMA_BIN" ] && OLLAMA_BIN="$DATA_DIR/ollama/ollama-$PLATFORM"
    if [ ! -x "$OLLAMA_BIN" ]; then
        echo -e "  ${YELLOW}[!] Ollama not found!${RESET}"
        setup_provider; return
    fi
    export OLLAMA_MODELS="$DATA_DIR/ollama/data"
    "$OLLAMA_BIN" serve >/dev/null 2>&1 & TMP_PID=$!; sleep 2
    models=$("$OLLAMA_BIN" list 2>/dev/null | awk 'NR>1 {print $1}')
    kill "$TMP_PID" 2>/dev/null; wait "$TMP_PID" 2>/dev/null || true
    if [ -z "$models" ]; then echo -e "  ${YELLOW}[!] No local models${RESET}"; sleep 1; setup_provider; return; fi
    pick_model "$models" "Select model:"
    save_env "AI_PROVIDER=ollama
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=ollama
OPENAI_BASE_URL=http://localhost:11434/v1
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_lmstudio() {
    echo "  Start LM Studio, load a model, enable Developer > Local Server"
    read -p "  Base URL [http://localhost:1234/v1]: " b; [ -z "$b" ] && b="http://localhost:1234/v1"
    b="${b%/}"
    if ! curl -sf -H "Authorization: Bearer lm-studio" "${b}/models" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Cannot reach LM Studio${RESET}"
        read -p "  Continue? (y/N): " c; [[ ! "$c" =~ ^[Yy]$ ]] && setup_lmstudio && return
    fi
    models=$(curl -sf -H "Authorization: Bearer lm-studio" "${b}/models" 2>/dev/null | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"id" *: *"//;s/"//g')
    [ -z "$models" ] && read -p "  Model name: " USER_MODEL || pick_model "$models" "Select model:"
    [ -z "$USER_MODEL" ] && read -p "  Model name: " USER_MODEL
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=lm-studio
OPENAI_BASE_URL=${b}
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

setup_custom_openai() {
    read -p "  Base URL (e.g. https://api.example.com/v1): " b; [ -z "$b" ] && setup_custom_openai && return
    b="${b%/}"; read -p "  API Key (Enter for none): " k; [ -z "$k" ] && k="not-needed"
    if ! curl -sf -H "Authorization: Bearer $k" "${b}/models" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Cannot verify ${b}/models${RESET}"
        read -p "  Continue? (y/N): " c; [[ ! "$c" =~ ^[Yy]$ ]] && setup_custom_openai && return
    fi
    models=$(curl -sf -H "Authorization: Bearer $k" "${b}/models" 2>/dev/null | grep -Eo '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"id" *: *"//;s/"//g')
    [ -z "$models" ] && read -p "  Model: " USER_MODEL || pick_model "$models" "Select model [Enter for manual]:"
    [ -z "$USER_MODEL" ] && read -p "  Model: " USER_MODEL
    save_env "AI_PROVIDER=openai
CLAUDE_CODE_USE_OPENAI=1
OPENAI_API_KEY=$k
OPENAI_BASE_URL=${b}
OPENAI_API_FORMAT=chat_completions
OPENAI_MODEL=${USER_MODEL}
AI_DISPLAY_MODEL=${USER_MODEL}"
}

# ─── Run Provider Setup if needed ──────────────────────────
if [ "$goto_loaded" -eq 0 ]; then
    setup_provider
    echo -e "\n  ${GREEN}[OK] Settings saved!${RESET}\n"
    ENV_CONTENT="$(tr -d '\r' < "$ENV_FILE" 2>/dev/null || true)"
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.* ]] && continue; [ -z "$key" ] && continue
        export "$key=$value"
    done <<< "$ENV_CONTENT"
fi

# ─── Provider Name ─────────────────────────────────────────
[ "$AI_PROVIDER" = "openai" ] && [ -n "$OPENAI_BASE_URL" ] && [ -z "$OPENAI_API_FORMAT" ] && export OPENAI_API_FORMAT="chat_completions"
export CLAUDE_CODE_PROVIDER_PROFILE_ENV_APPLIED=1
export CLAUDE_CODE_PROVIDER_PROFILE_ENV_APPLIED_ID=portable-env

PROVIDER_NAME="$AI_PROVIDER"
case "$AI_PROVIDER" in
    openai)
        case "$OPENAI_BASE_URL" in
            *openrouter*) PROVIDER_NAME="OpenRouter" ;;
            *integrate.api.nvidia.com*) PROVIDER_NAME="NVIDIA NIM" ;;
            *api.deepseek.com*) PROVIDER_NAME="DeepSeek" ;;
            *api.openai.com*) PROVIDER_NAME="OpenAI" ;;
            *localhost:11434*) PROVIDER_NAME="Ollama" ;;
            *localhost:1234*) PROVIDER_NAME="LM Studio" ;;
            *) PROVIDER_NAME="Custom API" ;;
        esac ;;
    gemini) PROVIDER_NAME="Google Gemini" ;;
    anthropic) PROVIDER_NAME="Anthropic Claude" ;;
    ollama) PROVIDER_NAME="Ollama (Local)" ;;
esac

echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${BOLD}OpenClaude Portable - Ready${RESET}"
echo -e "${CYAN}=========================================================${RESET}"
echo -e "  ${BOLD}Provider${RESET} : ${GREEN}${PROVIDER_NAME}${RESET}"
echo -e "  ${BOLD}Model${RESET}    : ${GREEN}${AI_DISPLAY_MODEL}${RESET}"
echo -e "  ${BOLD}Data${RESET}     : ${DIM}Portable (zero footprint)${RESET}"
echo -e "${CYAN}=========================================================${RESET}"
echo ""

# ─── Launch Menu ───────────────────────────────────────────
CMD_ARGS=""
if [ $QUICK_MODE -eq 1 ]; then
    echo -e "  ${RED}${BOLD}LIMITLESS MODE - Auto-executes everything${RESET}"
    CMD_ARGS="--dangerously-skip-permissions"
else
    while true; do
        echo -e "  ${BOLD}Select:${RESET}"
        echo -e "  ${CYAN}1)${RESET} ${GREEN}Launch AI${RESET}      ${DIM}- Normal (auto 10s)${RESET}"
        echo -e "  ${CYAN}2)${RESET} ${RED}Limitless Mode${RESET} ${DIM}- No approval prompts${RESET}"
        echo -e "  ${DIM}────────────────────────${RESET}"
        echo -e "  ${CYAN}3)${RESET} Dashboard    ${DIM}- Web UI${RESET}"
        echo -e "  ${CYAN}4)${RESET} Change Provider"
        echo -e "  ${CYAN}5)${RESET} Setup Offline${DIM}- Ollama models${RESET}"
        echo ""

        # Termux-compatible countdown (no -n flag)
        LAUNCH_MODE=""
        for i in 9 8 7 6 5 4 3 2 1 0; do
            echo -ne "\r  Action (1-5) [auto ${i}]: "
            if [ "$TERMUX_MODE" -eq 1 ]; then
                read -t 1 LAUNCH_MODE 2>/dev/null && [ -n "$LAUNCH_MODE" ] && break
            else
                read -t 1 -n 1 LAUNCH_MODE 2>/dev/null && [ -n "$LAUNCH_MODE" ] && break
            fi
            LAUNCH_MODE=""
        done
        [ -z "$LAUNCH_MODE" ] && LAUNCH_MODE="1"
        echo ""

        case "$LAUNCH_MODE" in
            1) echo -e "  ${GREEN}Normal mode${RESET}"; break ;;
            2) echo -e "  ${RED}LIMITLESS MODE${RESET}"; CMD_ARGS="--dangerously-skip-permissions"; break ;;
            3) exec bash "$ROOT_DIR/tools/open_dashboard.sh" ;;
            4) exec bash "$ROOT_DIR/tools/change_provider.sh" ;;
            5) exec bash "$ROOT_DIR/tools/setup_local_models.sh" ;;
            *) echo -e "  ${RED}Invalid${RESET}\n" ;;
        esac
    done
fi

# ─── Launch Engine ─────────────────────────────────────────
if [ "$AI_PROVIDER" = "ollama" ]; then
    OLLAMA_BIN="$DATA_DIR/ollama/ollama"
    [ ! -f "$OLLAMA_BIN" ] && OLLAMA_BIN="$DATA_DIR/ollama/ollama-$PLATFORM"
    if [ -x "$OLLAMA_BIN" ]; then
        echo -e "  ${CYAN}[~] Starting Local Ollama...${RESET}"
        export OLLAMA_MODELS="$DATA_DIR/ollama/data"
        "$OLLAMA_BIN" serve >/dev/null 2>&1 &
        OLLAMA_PID=$!; sleep 3
    fi
fi

echo -e "  ${CYAN}[~] Starting AI Engine...${RESET}"
echo ""

PROVIDER_ARGS=()
case "$AI_PROVIDER" in
    anthropic) PROVIDER_ARGS=(--provider anthropic) ;;
    gemini)    PROVIDER_ARGS=(--provider gemini) ;;
    ollama)    PROVIDER_ARGS=(--provider ollama) ;;
    openai)    [[ "$OPENAI_BASE_URL" == *"integrate.api.nvidia.com"* ]] && PROVIDER_ARGS=(--provider nvidia-nim) ;;
esac

MODEL_ARGS=()
[ -n "$OPENAI_MODEL" ] && MODEL_ARGS=(--model "$OPENAI_MODEL")
[ -n "$GEMINI_MODEL" ] && MODEL_ARGS=(--model "$GEMINI_MODEL")
[ -n "$ANTHROPIC_MODEL" ] && MODEL_ARGS=(--model "$ANTHROPIC_MODEL")

cd "$ENGINE_DIR"
if [ -f "$OC_BIN" ]; then
    "$NODE_BIN" "$OC_BIN" --setting-sources local "${PROVIDER_ARGS[@]}" "${MODEL_ARGS[@]}" $CMD_ARGS
else
    echo -e "  ${RED}[ERROR] OpenClaude Engine missing. Re-run ./start.sh${RESET}"
    exit 1
fi

if [ -n "$OLLAMA_PID" ]; then
    echo -e "  ${CYAN}[~] Stopping Ollama...${RESET}"
    kill "$OLLAMA_PID" 2>/dev/null; wait "$OLLAMA_PID" 2>/dev/null
fi
