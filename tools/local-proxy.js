#!/usr/bin/env node
/**
 * local-proxy.js — Ollama System Prompt Trimmer & Proxy
 *
 * Sits between OpenClaude and Ollama to:
 *   1. Trim system prompts to ~300 tokens for faster local inference
 *   2. Forward all requests transparently
 *   3. Provide health check endpoints
 *
 * OpenClaude -> localhost:11435 (this proxy) -> localhost:11434 (Ollama)
 *
 * All output goes to data/proxy.log — never stdout/stderr.
 */

const http = require("http");
const fs   = require("fs");
const path = require("path");

const PROXY_PORT  = parseInt(process.env.PROXY_PORT || "11435", 10);
const OLLAMA_HOST = process.env.OLLAMA_HOST || "127.0.0.1";
const OLLAMA_PORT = parseInt(process.env.OLLAMA_PORT || "11434", 10);

const LOG_FILE = path.join(__dirname, "..", "data", "proxy.log");
const PID_FILE = path.join(__dirname, "..", "data", "proxy.pid");

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  try {
    fs.appendFileSync(LOG_FILE, line);
  } catch { /* silent */ }
}

// Write PID file for cleanup
try {
  fs.writeFileSync(PID_FILE, String(process.pid));
} catch { /* silent */ }

process.on("SIGINT", () => {
  log("Proxy shutting down (SIGINT)");
  try { fs.unlinkSync(PID_FILE); } catch {}
  process.exit(0);
});
process.on("SIGTERM", () => {
  log("Proxy shutting down (SIGTERM)");
  try { fs.unlinkSync(PID_FILE); } catch {}
  process.exit(0);
});

// ---------------------------------------------------------------------------
// System prompt trimmer
// ---------------------------------------------------------------------------
const MAX_CHARS = 1200;

function trimSystemPrompt(content) {
  if (typeof content !== "string") return content;
  if (content.length <= MAX_CHARS) return content;
  const cut = content.lastIndexOf(". ", MAX_CHARS);
  const trimPoint = cut > MAX_CHARS * 0.6 ? cut + 1 : MAX_CHARS;
  return (
    content.slice(0, trimPoint).trimEnd() +
    "\n\n[System prompt truncated for local model performance]"
  );
}

function optimizeMessages(messages) {
  if (!Array.isArray(messages)) return messages;
  return messages.map((msg) => {
    if (msg.role !== "system") return msg;
    if (typeof msg.content === "string") {
      return { ...msg, content: trimSystemPrompt(msg.content) };
    }
    if (Array.isArray(msg.content)) {
      return {
        ...msg,
        content: msg.content.map((part) => {
          if (part.type === "text") {
            return { ...part, text: trimSystemPrompt(part.text) };
          }
          return part;
        }),
      };
    }
    return msg;
  });
}

// ---------------------------------------------------------------------------
// Proxy server
// ---------------------------------------------------------------------------
const server = http.createServer((req, res) => {
  // ── Health check ──────────────────────────────────────────
  if (req.url === "/health" && req.method === "GET") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      status: "ok",
      proxyPort: PROXY_PORT,
      ollamaHost: OLLAMA_HOST,
      ollamaPort: OLLAMA_PORT,
      pid: process.pid,
    }));
    return;
  }

  let body = [];

  req.on("data", (chunk) => body.push(chunk));

  req.on("end", () => {
    let rawBody = Buffer.concat(body);
    let modifiedBody = rawBody;

    if (req.method === "POST" && req.url.includes("/chat/completions")) {
      try {
        const json = JSON.parse(rawBody.toString("utf8"));
        if (json.messages) {
          const before = JSON.stringify(json.messages).length;
          json.messages = optimizeMessages(json.messages);
          const after  = JSON.stringify(json.messages).length;
          const saved  = Math.round(((before - after) / before) * 100);
          if (saved > 0) {
            log(`Trimmed: ${before} -> ${after} chars (${saved}% reduction)`);
          }
        }
        modifiedBody = Buffer.from(JSON.stringify(json), "utf8");
      } catch {
        modifiedBody = rawBody;
      }
    }

    const options = {
      hostname: OLLAMA_HOST,
      port:     OLLAMA_PORT,
      path:     req.url,
      method:   req.method,
      headers: {
        ...req.headers,
        host:             `${OLLAMA_HOST}:${OLLAMA_PORT}`,
        "content-length": modifiedBody.length,
      },
    };

    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res, { end: true });
    });

    proxyReq.on("error", (err) => {
      log(`Ollama connection error: ${err.message}`);
      res.writeHead(502);
      res.end(JSON.stringify({ error: "Ollama unreachable: " + err.message }));
    });

    proxyReq.write(modifiedBody);
    proxyReq.end();
  });
});

server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    log(`Port ${PROXY_PORT} already in use - reusing existing proxy instance`);
    process.exit(0);
  }
  log(`Server error: ${err.message}`);
  process.exit(1);
});

server.listen(PROXY_PORT, "127.0.0.1", () => {
  log(`Proxy started on :${PROXY_PORT} -> Ollama :${OLLAMA_PORT} (PID ${process.pid})`);
});
