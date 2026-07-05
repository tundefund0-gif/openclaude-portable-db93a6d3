# OpenClaude Portable

> Zero-footprint AI coding agent — run from any folder, USB drive, or Android phone.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20Android(Termux)-lightgrey.svg)]()

Powers the [OpenClaude](https://github.com/gitlawb/openclaude) engine with a self-contained Node.js runtime, 9 AI providers, web dashboard, and full offline support.

---

## Quick Start

**Windows:** `.\START.bat`

**Linux / macOS:**
```bash
chmod +x start.sh && ./start.sh
```

**Termux (Android):**
```bash
git clone --depth=1 https://github.com/tundefund0-gif/openclaude-portable-db93a6d3.git ~/openclaude-portable && bash ~/openclaude-portable/termux-setup.sh
cd ~/openclaude-portable && ./start.sh
```

---

## Tools

| Command | Description |
|---|---|
| `./start.sh` | Main launcher - setup provider, launch AI |
| `bash tools/opencode-doctor.sh` | Diagnostics - check all components |
| `bash tools/opencode-update.sh` | Self-updater - git pull + reinstall engine |
| `bash tools/open_dashboard.sh` | Web dashboard at localhost:3000 |
| `bash tools/change_provider.sh` | Switch AI provider or API key |
| `bash tools/setup_local_models.sh` | Download local Ollama models |
| `bash termux-setup.sh` | Termux one-time environment setup |

---

## Providers

NVIDIA NIM, DeepSeek, OpenRouter, Google Gemini, Anthropic Claude, OpenAI, Ollama (offline), LM Studio, Custom OpenAI-compatible API.

---

## Requirements

- **Windows 10+** - nothing needed
- **Linux / macOS** - curl
- **Termux** - pkg install nodejs curl git, or use termux-setup.sh

---

## License

MIT
