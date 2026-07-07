# OpenClaude Portable v1.1.0

> Zero-footprint AI coding agent — run from any folder, thumb drive, or Android phone.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Powers the [OpenClaude](https://github.com/gitlawb/openclaude) engine with a self-contained Node.js runtime, 9 AI providers, a web dashboard, Ollama local models, and full offline support.

---

## Quick Start

**Linux / macOS:**
```bash
chmod +x start.sh && ./start.sh
```

**Windows:**
```
Double-click START.bat
```

**Termux (Android):**
```bash
git clone --depth=1 https://github.com/tundefund0-gif/openclaude-portable-db93a6d3.git ~/openclaude-portable
bash ~/openclaude-portable/termux-setup.sh
cd ~/openclaude-portable && ./start.sh
```

---

## Usage

```
./start.sh [OPTIONS]

Options:
    --quick           Skip permissions (Limitless mode)
    --offline         Skip update checks
    --reset-config    Re-run provider setup
    --doctor          Run diagnostics
    --update          Pull latest + reinstall
    --version, -v     Show version
    --help, -h        Show this help
```

### Menu Actions

| # | Action | Description |
|---|--------|-------------|
| 1 | Launch AI | Start coding with your configured provider |
| 2 | Limitless | No approval prompts (dangerous) |
| 3 | Dashboard | Web UI at http://localhost:3000 |
| 4 | Change Provider | Switch AI provider or API key |
| 5 | Install Ollama | Local offline models |

---

## Providers

| Provider | Type | Free Tier |
|----------|------|-----------|
| OpenRouter | API | 200+ free models |
| NVIDIA NIM | API | Free GPU credits |
| DeepSeek | API | Pay-per-token |
| Google Gemini | API | Free tier available |
| Anthropic Claude | API | Pay-per-token |
| OpenAI | API | Pay-per-token |
| Ollama | Local | Fully free & offline |
| LM Studio | Local | Fully free |
| Custom API | Any | OpenAI-compatible |

---

## Tools

| Command | Description |
|---|---|
| `bash tools/opencode-doctor.sh` | Full diagnostics |
| `bash tools/opencode-update.sh` | Git pull + reinstall engine |
| `bash tools/open_dashboard.sh` | Launch web dashboard |
| `bash tools/change_provider.sh` | Switch provider/keys |
| `bash tools/setup_local_models.sh` | Download Ollama models |
| `bash termux-setup.sh` | Termux environment setup |

---

## Requirements

- **Windows 10+** — nothing needed
- **Linux / macOS** — curl
- **Termux** — `pkg install nodejs curl git` (or use `termux-setup.sh`)

---

## Project Structure

```
openclaude-portable/
├── start.sh              Main launcher
├── termux-setup.sh       Termux environment setup
├── START.bat             Windows launcher
├── dashboard/            Web dashboard (SPA)
│   ├── server.mjs        Express-like HTTP server with agent loop
│   └── index.html        Full chat UI (1648 lines)
├── tools/
│   ├── opencode-doctor.sh      Diagnostics
│   ├── opencode-update.sh      Self-updater
│   ├── open_dashboard.sh       Dashboard launcher
│   ├── change_provider.sh      9-provider config UI
│   ├── setup_local_models.sh   Ollama model installer
│   ├── local-proxy.js          Ollama prompt trimmer proxy
│   ├── *.bat                   Windows wrappers
│   └── *.ps1                  PowerShell installers
├── data/                 Runtime data (gitignored)
│   ├── ai_settings.env   Provider config
│   ├── home/             Portable $HOME
│   ├── openclaude/       Engine config
│   ├── ollama/           Ollama binary + data
│   ├── chats/            Dashboard chat history
│   └── npm-cache/        npm cache
└── engine/               Bundled Node.js + openclaude package
```

---

## License

MIT
