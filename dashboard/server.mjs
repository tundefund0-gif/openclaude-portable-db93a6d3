import { createServer } from 'http';
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync, mkdirSync, unlinkSync } from 'fs';
import { join, dirname, resolve, relative, isAbsolute } from 'path';
import { fileURLToPath } from 'url';
import { execSync, exec } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = join(__dirname, '..'); // Portable_AI_USB root
const DATA_DIR = join(ROOT_DIR, 'data');
const ENV_FILE = join(DATA_DIR, 'ai_settings.env');
const CHATS_DIR = join(DATA_DIR, 'chats');
const HTML_FILE = join(__dirname, 'index.html');
const IS_WIN = process.platform === 'win32';
const IS_MAC = process.platform === 'darwin';
// Auto-detect platform engine directory
const PLATFORM_DIR = IS_WIN ? 'win' : IS_MAC ? 'darwin' : 'linux';
const ARCH_DIR = process.arch === 'x64' || process.arch === 'amd64' ? 'x64' : 'arm64';
const BIN_DIR = join(ROOT_DIR, 'engine', `node-${PLATFORM_DIR}-${ARCH_DIR}`, 'bin');
const PORT = process.env.PORT || 3000;
const IS_TERMUX = process.env.PREFIX && process.platform === 'linux' && process.arch === 'arm64';

// Allow SSL override via env (for corporate proxies, self-signed certs, etc.)
if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0') {
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
    console.log('  [i] TLS verification disabled (NODE_TLS_REJECT_UNAUTHORIZED=0)');
}
let WORK_DIR = ROOT_DIR; // Default working directory

// ─── Helpers ─────────────────────────────────────────────────

function readConfig() {
    if (!existsSync(ENV_FILE)) return {};
    const raw = readFileSync(ENV_FILE, 'utf-8');
    const config = {};
    for (const line of raw.split('\n')) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const idx = trimmed.indexOf('=');
        if (idx === -1) continue;
        config[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
    }
    return config;
}

function writeConfig(config) {
    if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
    const lines = ['# ========================================================', '# Portable AI - Master Switchboard', '# ========================================================'];
    for (const [key, value] of Object.entries(config)) lines.push(`${key}=${value}`);
    writeFileSync(ENV_FILE, lines.join('\n') + '\n', 'utf-8');
}

function readBody(req) {
    return new Promise((resolve, reject) => {
        let data = '';
        req.on('data', chunk => data += chunk);
        req.on('end', () => { try { resolve(JSON.parse(data)); } catch { reject(new Error('Invalid JSON')); } });
    });
}

function readBodyRaw(req) {
    return new Promise(resolve => {
        let data = '';
        req.on('data', chunk => data += chunk);
        req.on('end', () => resolve(data));
    });
}

async function fetchExternal(url, headers = {}, body = null, method = 'GET', attempt = 1) {
    const maxAttempts = 3;
    const mod = await import(url.startsWith('https') ? 'https' : 'http');
    return new Promise((resolve, reject) => {
        const opts = { method, headers, rejectUnauthorized: process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0' };
        const req = mod.request(url, opts, res => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve({ status: res.statusCode, data, headers: res.headers }));
        });
        req.on('error', (err) => {
            if (isSSLError(err) && attempt < maxAttempts) {
                const delay = Math.min(1000 * Math.pow(2, attempt), 10000);
                setTimeout(() => {
                    fetchExternal(url, headers, body, method, attempt + 1).then(resolve).catch(reject);
                }, delay);
            } else {
                reject(err);
            }
        });
        req.setTimeout(300000, () => { req.destroy(); reject(new Error('Timeout after 300s')); });
        if (body) req.write(body);
        req.end();
    });
}

async function streamExternal(url, headers, body, onChunk, onEnd) {
    const mod = await import(url.startsWith('https') ? 'https' : 'http');
    return new Promise((resolve, reject) => {
        const req = mod.request(url, { method: 'POST', headers, rejectUnauthorized: process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0' }, res => {
            res.on('data', chunk => onChunk(chunk.toString()));
            res.on('end', () => { onEnd(); resolve(); });
            res.on('error', reject);
        });
        req.on('error', reject);
        req.setTimeout(300000, () => { req.destroy(); reject(new Error('Timeout after 300s')); });
        req.write(body);
        req.end();
    });
}

function sendJSON(res, status, obj) {
    res.writeHead(status, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    res.end(JSON.stringify(obj));
}

function getInstalledVersion() {
    // Check the engine directory for openclaude
    try {
        const pkg = join(ROOT_DIR, 'engine', 'node_modules', '@gitlawb', 'openclaude', 'package.json');
        if (existsSync(pkg)) return JSON.parse(readFileSync(pkg, 'utf-8')).version;
    } catch {}
    return null;
}

function getLatestVersion() {
    try {
        const npm = join(BIN_DIR, IS_WIN ? 'npm.cmd' : 'npm');
        const cwd = join(ROOT_DIR, 'engine');
        return execSync(`"${npm}" view @gitlawb/openclaude version`, { cwd, encoding: 'utf-8', timeout: 30000 }).trim();
    } catch { return null; }
}

function getSystemInfo() {
    const whichCmd = IS_WIN ? 'where' : 'which';
    const info = {
        nodeVersion: process.version, platform: process.platform, arch: process.arch,
        hasGit: IS_WIN ? existsSync(join(BIN_DIR, 'git', 'cmd', 'git.exe')) || (() => { try { execSync('where git', { stdio: 'pipe' }); return true; } catch { return false; } })()
            : (() => { try { execSync('which git', { stdio: 'pipe' }); return true; } catch { return false; } })(),
        hasPython: IS_WIN ? existsSync(join(BIN_DIR, 'python', 'python.exe')) || (() => { try { execSync('where python', { stdio: 'pipe' }); return true; } catch { return false; } })()
            : (() => { try { execSync('which python3 || which python', { stdio: 'pipe' }); return true; } catch { return false; } })(),
        portableGit: IS_WIN && existsSync(join(BIN_DIR, 'git', 'cmd', 'git.exe')),
        portablePython: IS_WIN && existsSync(join(BIN_DIR, 'python', 'python.exe')),
        engineVersion: getInstalledVersion(),
        ollamaInstalled: existsSync(join(DATA_DIR, 'ollama', 'ollama.exe')) || existsSync(join(DATA_DIR, 'ollama', 'ollama')),
        diskFree: 0, diskTotal: 0,
    };
    try {
        if (IS_WIN) {
            const drive = ROOT_DIR.charAt(0);
            const out = execSync(`wmic logicaldisk where "DeviceID='${drive}:'" get FreeSpace,Size /format:csv`, { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] });
            const lines = out.trim().split('\n').filter(l => l.trim());
            const last = lines[lines.length - 1].split(',');
            info.diskFree = parseInt(last[1]) || 0;
            info.diskTotal = parseInt(last[2]) || 0;
        } else {
            const out = execSync(`df -k "${ROOT_DIR}" | tail -1`, { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] });
            const parts = out.trim().split(/\s+/);
            info.diskTotal = (parseInt(parts[1]) || 0) * 1024;
            info.diskFree = (parseInt(parts[3]) || 0) * 1024;
        }
    } catch {}
    return info;
}

function getSessionLogs() {
    const logsDir = join(DATA_DIR, 'app_data');
    const logs = [];
    if (!existsSync(logsDir)) return logs;
    function walkDir(dir, depth = 0) {
        if (depth > 3) return;
        try {
            for (const entry of readdirSync(dir)) {
                const fullPath = join(dir, entry);
                try {
                    const stat = statSync(fullPath);
                    if (stat.isDirectory()) walkDir(fullPath, depth + 1);
                    else if (['.json','.log','.md','.txt'].some(ext => entry.endsWith(ext)))
                        logs.push({ name: entry, path: fullPath.replace(ROOT_DIR, ''), size: stat.size, modified: stat.mtime.toISOString() });
                } catch {}
            }
        } catch {}
    }
    walkDir(logsDir);
    return logs.sort((a, b) => new Date(b.modified) - new Date(a.modified)).slice(0, 50);
}

// ─── Chat History ─────────────────────────────────────────────

function ensureChatsDir() {
    if (!existsSync(CHATS_DIR)) mkdirSync(CHATS_DIR, { recursive: true });
}

function listChats() {
    ensureChatsDir();
    return readdirSync(CHATS_DIR)
        .filter(f => f.endsWith('.json'))
        .map(f => {
            const full = join(CHATS_DIR, f);
            try {
                const data = JSON.parse(readFileSync(full, 'utf-8'));
                return { id: f.replace('.json', ''), title: data.title || 'Untitled', created: data.created, updated: data.updated, messageCount: (data.messages || []).length };
            } catch { return null; }
        })
        .filter(Boolean)
        .sort((a, b) => new Date(b.updated) - new Date(a.updated));
}

function loadChat(id) {
    const file = join(CHATS_DIR, `${id}.json`);
    if (!existsSync(file)) return null;
    return JSON.parse(readFileSync(file, 'utf-8'));
}

function saveChat(id, data) {
    ensureChatsDir();
    writeFileSync(join(CHATS_DIR, `${id}.json`), JSON.stringify(data, null, 2), 'utf-8');
}

function deleteChat(id) {
    const file = join(CHATS_DIR, `${id}.json`);
    if (existsSync(file)) { unlinkSync(file); }
}

function newChatId() {
    return `chat_${Date.now()}`;
}

// ═══════════════════════════════════════════════════════════════
//  AGENT SYSTEM — Tool Definitions, Executors, and Agentic Loop
// ═══════════════════════════════════════════════════════════════

// ─── Tool Definitions ────────────────────────────────────────

const TOOL_DEFS = [
    {
        name: 'think',
        description: 'Use this to think and plan before taking actions. Describe your plan, what files you need to read, what commands to run, and the expected outcome. This costs no tokens and does not execute anything.',
        parameters: {
            type: 'object',
            properties: {
                plan: { type: 'string', description: 'Your step-by-step plan for what to do next' }
            },
            required: ['plan']
        }
    },
    {
        name: 'write_file',
        description: 'Create or overwrite a file with the given content. Creates parent directories automatically.',
        parameters: {
            type: 'object',
            properties: {
                path: { type: 'string', description: 'File path relative to the working directory' },
                content: { type: 'string', description: 'The full content to write to the file' }
            },
            required: ['path', 'content']
        }
    },
    {
        name: 'edit_file',
        description: 'Make targeted edits to an existing file. Provide the old string to find and the new string to replace it with. Use this for small changes instead of rewriting the entire file.',
        parameters: {
            type: 'object',
            properties: {
                path: { type: 'string', description: 'File path relative to the working directory' },
                old_string: { type: 'string', description: 'The exact text to find and replace' },
                new_string: { type: 'string', description: 'The replacement text' }
            },
            required: ['path', 'old_string', 'new_string']
        }
    },
    {
        name: 'read_file',
        description: 'Read the contents of a file.',
        parameters: {
            type: 'object',
            properties: {
                path: { type: 'string', description: 'File path relative to the working directory' }
            },
            required: ['path']
        }
    },
    {
        name: 'list_directory',
        description: 'List all files and subdirectories in a directory.',
        parameters: {
            type: 'object',
            properties: {
                path: { type: 'string', description: 'Directory path relative to working directory. Use "." for current directory.' }
            },
            required: ['path']
        }
    },
    {
        name: 'execute_command',
        description: 'Execute a shell command and return its output. Use this for running scripts, installing packages, compiling code, git operations, etc. For long-running commands, output is streamed incrementally.',
        parameters: {
            type: 'object',
            properties: {
                command: { type: 'string', description: 'The shell command to execute' }
            },
            required: ['command']
        }
    },
    {
        name: 'search_files',
        description: 'Search for a text pattern in files within a directory. Returns matching lines with file names and line numbers.',
        parameters: {
            type: 'object',
            properties: {
                pattern: { type: 'string', description: 'Text pattern to search for' },
                path: { type: 'string', description: 'Directory to search in, relative to working directory. Use "." for current directory.' }
            },
            required: ['pattern', 'path']
        }
    }
];

// Provider-specific tool format converters
function toolsForOpenAI() {
    return TOOL_DEFS.map(t => ({
        type: 'function',
        function: { name: t.name, description: t.description, parameters: t.parameters }
    }));
}

function toolsForAnthropic() {
    return TOOL_DEFS.map(t => ({
        name: t.name, description: t.description, input_schema: t.parameters
    }));
}

function toolsForGemini() {
    return [{ function_declarations: TOOL_DEFS.map(t => ({
        name: t.name, description: t.description, parameters: t.parameters
    })) }];
}

// ─── Tool Executors ──────────────────────────────────────────

function resolvePath(relPath) {
    const abs = isAbsolute(relPath) ? relPath : join(WORK_DIR, relPath);
    return resolve(abs);
}

const WRITE_TOOLS = new Set(['write_file', 'execute_command']);

function executeTool(name, args) {
    try {
        switch (name) {
            case 'think': {
                return { success: true, message: `Plan noted: ${(args.plan || '').slice(0, 200)}...`, thinking: args.plan || '' };
            }
            case 'write_file': {
                const fullPath = resolvePath(args.path);
                const dir = dirname(fullPath);
                if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
                writeFileSync(fullPath, args.content, 'utf-8');
                return { success: true, message: `File written: ${args.path} (${args.content.length} chars)`, path: args.path, size: args.content.length };
            }
            case 'edit_file': {
                const fullPath = resolvePath(args.path);
                if (!existsSync(fullPath)) return { success: false, error: `File not found: ${args.path}` };
                const content = readFileSync(fullPath, 'utf-8');
                const oldStr = args.old_string;
                if (!content.includes(oldStr)) return { success: false, error: `old_string not found in file ${args.path}` };
                const newContent = content.replace(oldStr, args.new_string);
                if (newContent === content) return { success: false, error: 'Edit produced no changes' };
                writeFileSync(fullPath, newContent, 'utf-8');
                return { success: true, message: `File edited: ${args.path} (${oldStr.length} chars replaced)`, path: args.path };
            }
            case 'read_file': {
                const fullPath = resolvePath(args.path);
                if (!existsSync(fullPath)) return { success: false, error: `File not found: ${args.path}` };
                const content = readFileSync(fullPath, 'utf-8');
                return { success: true, content, size: content.length, path: args.path };
            }
            case 'list_directory': {
                const fullPath = resolvePath(args.path || '.');
                if (!existsSync(fullPath)) return { success: false, error: `Directory not found: ${args.path}` };
                const entries = readdirSync(fullPath).map(name => {
                    try {
                        const stat = statSync(join(fullPath, name));
                        return { name, type: stat.isDirectory() ? 'directory' : 'file', size: stat.isFile() ? stat.size : undefined };
                    } catch { return { name, type: 'unknown' }; }
                });
                return { success: true, path: args.path || '.', entries };
            }
            case 'execute_command': {
                try {
                    const output = execSync(args.command, {
                        cwd: WORK_DIR, encoding: 'utf-8', timeout: 300000,
                        stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 50 * 1024 * 1024
                    });
                    return { success: true, output: output.slice(0, 50000), exitCode: 0 };
                } catch (e) {
                    return { success: false, output: (e.stdout || '').slice(0, 30000), error: (e.stderr || e.message || '').slice(0, 20000), exitCode: e.status || 1 };
                }
            }
            case 'search_files': {
                try {
                    const searchPath = resolvePath(args.path || '.');
                    const cmd = process.platform === 'win32'
                        ? `findstr /S /N /I /C:"${args.pattern}" "${searchPath}\\*"`
                        : `grep -rnI "${args.pattern}" "${searchPath}" --include="*" | head -200`;
                    const output = execSync(cmd, { encoding: 'utf-8', timeout: 60000, stdio: ['pipe', 'pipe', 'pipe'] });
                    return { success: true, matches: output.slice(0, 50000) };
                } catch (e) {
                    if (e.status === 1) return { success: true, matches: '', message: 'No matches found' };
                    return { success: false, error: e.message };
                }
            }
            default:
                return { success: false, error: `Unknown tool: ${name}` };
        }
    } catch (e) {
        return { success: false, error: e.message };
    }
}

// ─── Non-Streaming AI Calls (for tool loop) ──────────────────

async function callAI_OpenAI(messages, cfg, includeTools = true) {
    const model = cfg.OPENAI_MODEL || cfg.AI_DISPLAY_MODEL;
    const baseUrl = cfg.OPENAI_BASE_URL || 'https://api.openai.com/v1';
    const apiKey = cfg.OPENAI_API_KEY;
    const payload = { model, messages, max_tokens: 131072, stream: false };
    if (includeTools) payload.tools = toolsForOpenAI();
    const body = JSON.stringify(payload);
    const headers = {
        'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}`,
        'Content-Length': String(Buffer.byteLength(body))
    };
    if (cfg.OPENAI_BASE_URL?.includes('openrouter')) {
        headers['HTTP-Referer'] = 'http://localhost:3000';
        headers['X-Title'] = 'Portable AI Agent';
    }
    const resp = await fetchExternal(`${baseUrl}/chat/completions`, headers, body, 'POST');
    let data;
    try { data = JSON.parse(resp.data); } catch { throw new Error('Invalid response from AI API: ' + resp.data.slice(0, 300)); }
    // Check for API-level error
    if (data.error) {
        const errMsg = data.error.message || data.error.code || JSON.stringify(data.error);
        throw new Error(`API Error: ${errMsg}`);
    }
    const choice = data.choices?.[0]?.message;
    if (!choice) throw new Error('No response from AI: ' + resp.data.slice(0, 300));
    return {
        content: choice.content || '',
        toolCalls: (choice.tool_calls || []).map(tc => ({
            id: tc.id, name: tc.function.name,
            args: typeof tc.function.arguments === 'string' ? JSON.parse(tc.function.arguments) : tc.function.arguments
        })),
        rawMessage: choice
    };
}

async function callAI_Anthropic(messages, cfg, includeTools = true) {
    const model = cfg.AI_DISPLAY_MODEL || 'claude-3-5-sonnet-20241022';
    const apiKey = cfg.ANTHROPIC_API_KEY;
    // Extract system from messages
    let system = '';
    const filtered = [];
    for (const m of messages) {
        if (m.role === 'system') system = m.content;
        else filtered.push(m);
    }
    const payload = { model, messages: filtered, max_tokens: 131072 };
    if (system) payload.system = system;
    if (includeTools) payload.tools = toolsForAnthropic();
    const body = JSON.stringify(payload);
    const headers = {
        'Content-Type': 'application/json', 'x-api-key': apiKey,
        'anthropic-version': '2023-06-01', 'Content-Length': String(Buffer.byteLength(body))
    };
    const resp = await fetchExternal('https://api.anthropic.com/v1/messages', headers, body, 'POST');
    const data = JSON.parse(resp.data);
    if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));
    const textParts = (data.content || []).filter(c => c.type === 'text').map(c => c.text);
    const toolParts = (data.content || []).filter(c => c.type === 'tool_use');
    return {
        content: textParts.join('\n'),
        toolCalls: toolParts.map(tc => ({ id: tc.id, name: tc.name, args: tc.input })),
        stopReason: data.stop_reason
    };
}

async function callAI_Gemini(messages, cfg, includeTools = true) {
    const model = cfg.AI_DISPLAY_MODEL || 'gemini-2.0-pro-exp-02-05';
    const apiKey = cfg.GEMINI_API_KEY;
    // Convert messages to Gemini format
    const contents = [];
    for (const m of messages) {
        if (m.role === 'system') continue; // handled separately
        const role = m.role === 'assistant' ? 'model' : 'user';
        if (typeof m.content === 'string') {
            contents.push({ role, parts: [{ text: m.content }] });
        } else if (Array.isArray(m.parts)) {
            contents.push({ role, parts: m.parts });
        }
    }
    const payload = { contents };
    if (includeTools) payload.tools = toolsForGemini();
    // Add system instruction
    const sysMsg = messages.find(m => m.role === 'system');
    if (sysMsg) payload.system_instruction = { parts: [{ text: sysMsg.content }] };
    const body = JSON.stringify(payload);
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
    const headers = { 'Content-Type': 'application/json', 'Content-Length': String(Buffer.byteLength(body)) };
    const resp = await fetchExternal(url, headers, body, 'POST');
    const data = JSON.parse(resp.data);
    if (data.error) throw new Error(data.error.message || JSON.stringify(data.error));
    const parts = data.candidates?.[0]?.content?.parts || [];
    const textParts = parts.filter(p => p.text).map(p => p.text);
    const funcParts = parts.filter(p => p.functionCall);
    return {
        content: textParts.join('\n'),
        toolCalls: funcParts.map((p, i) => ({
            id: `gemini_call_${Date.now()}_${i}`, name: p.functionCall.name, args: p.functionCall.args || {}
        }))
    };
}

// Unified caller
async function callAI(messages, cfg, includeTools = true) {
    const provider = cfg.AI_PROVIDER;
    if (provider === 'openai' || provider === 'ollama') return callAI_OpenAI(messages, cfg, includeTools);
    if (provider === 'anthropic') return callAI_Anthropic(messages, cfg, includeTools);
    if (provider === 'gemini') return callAI_Gemini(messages, cfg, includeTools);
    throw new Error(`Unsupported provider for agent mode: ${provider}`);
}

// ─── Append tool results for each provider ───────────────────

function appendAssistantMessage(messages, aiResponse, provider) {
    if (provider === 'openai' || provider === 'ollama') {
        messages.push(aiResponse.rawMessage || {
            role: 'assistant', content: aiResponse.content || null,
            tool_calls: aiResponse.toolCalls.map(tc => ({
                id: tc.id, type: 'function',
                function: { name: tc.name, arguments: JSON.stringify(tc.args) }
            }))
        });
    } else if (provider === 'anthropic') {
        const content = [];
        if (aiResponse.content) content.push({ type: 'text', text: aiResponse.content });
        for (const tc of aiResponse.toolCalls) {
            content.push({ type: 'tool_use', id: tc.id, name: tc.name, input: tc.args });
        }
        messages.push({ role: 'assistant', content });
    } else if (provider === 'gemini') {
        const parts = [];
        if (aiResponse.content) parts.push({ text: aiResponse.content });
        for (const tc of aiResponse.toolCalls) {
            parts.push({ functionCall: { name: tc.name, args: tc.args } });
        }
        messages.push({ role: 'model', parts });
    }
}

function appendToolResult(messages, toolCall, result, provider) {
    const resultStr = typeof result === 'string' ? result : JSON.stringify(result);
    if (provider === 'openai' || provider === 'ollama') {
        messages.push({ role: 'tool', tool_call_id: toolCall.id, content: resultStr });
    } else if (provider === 'anthropic') {
        messages.push({ role: 'user', content: [{ type: 'tool_result', tool_use_id: toolCall.id, content: resultStr }] });
    } else if (provider === 'gemini') {
        messages.push({ role: 'user', parts: [{ functionResponse: { name: toolCall.name, response: { result } } }] });
    }
}

// ─── SSL/Network error detection ──────────────────────────
function isSSLError(err) {
    const msg = (err && (err.message || err.code || '').toLowerCase()) || '';
    return msg.includes('ssl') || msg.includes('tls') || msg.includes('bad record') ||
           msg.includes('certificate') || msg.includes('econnrefused') ||
           msg.includes('econnreset') || msg.includes('enotfound') ||
           msg.includes('etimedout') || msg.includes('eai_again') ||
           msg.includes('socket hang up') || msg.includes('network') ||
           msg.includes('fetch failed') || msg.includes('unreachable');
}

async function callAIWithRetry(messages, cfg, includeTools, sendSSE, attempt = 1) {
    const MAX_RETRIES = 3;
    try {
        return await callAI(messages, cfg, includeTools);
    } catch (e) {
        if (isSSLError(e) && attempt <= MAX_RETRIES) {
            const delay = Math.min(1000 * Math.pow(2, attempt), 15000);
            sendSSE({ type: 'agent_reasoning', content: `⚠️ Network/SSL error (attempt ${attempt}/${MAX_RETRIES}), retrying in ${delay/1000}s...`, iteration: 1 });
            await new Promise(r => setTimeout(r, delay));
            return callAIWithRetry(messages, cfg, includeTools, sendSSE, attempt + 1);
        }
        throw e;
    }
}

// ─── Agentic Loop ────────────────────────────────────────────

async function runAgent(allMessages, cfg, sendSSE) {
    const provider = cfg.AI_PROVIDER;
    const MAX_ITERATIONS = 1000;
    let finalText = '';

    const systemPrompt = `You are an autonomous AI coding agent with full file system and shell access. You MUST see every task through to completion — never stop mid-way. Available tools: think (plan without consuming tokens), write_file (create/edit files), edit_file (make targeted edits to existing files), read_file, list_directory, execute_command (run any shell command), search_files (grep). Working directory: ${WORK_DIR}. RULES: (1) Always start by using think tool to create a step-by-step plan. (2) Execute tasks directly using tools — never just describe what to do. (3) Never ask the user for permission or clarification — make reasonable assumptions and proceed. (4) If a command or tool fails, diagnose the issue and fix it. (5) For multi-step tasks, work systematically until fully complete. (6) Use edit_file for small edits instead of rewriting entire files. (7) Use execute_command for git operations, npm/pip installs, compiling, and any shell task. (8) When writing code, write complete, production-ready files. (9) Keep going until the task is 100% done. NEVER STOP MID-WAY.`;

    if (allMessages.length === 0 || allMessages[0].role !== 'system') {
        allMessages.unshift({ role: 'system', content: systemPrompt });
    }

    for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
        sendSSE({ type: 'agent_thinking', iteration: iter + 1 });

        let aiResponse;
        try {
            aiResponse = await callAIWithRetry(allMessages, cfg, true, sendSSE);
        } catch (e) {
            if (iter === 0) {
                try {
                    if (isSSLError(e)) {
                        sendSSE({ type: 'agent_reasoning', content: '⚠️ Network/SSL error. Trying without tools (fallback mode)...', iteration: 1 });
                    } else {
                        sendSSE({ type: 'agent_reasoning', content: 'Tool calling not supported by this model, falling back to chat mode...', iteration: 1 });
                    }
                    aiResponse = await callAIWithRetry(allMessages, cfg, false, sendSSE);
                } catch (e2) {
                    const errMsg = isSSLError(e2)
                        ? '⚠️ Network/SSL Error: Check your internet connection or proxy settings. If using a corporate network, try setting NODE_TLS_REJECT_UNAUTHORIZED=0'
                        : `⚠️ Agent Error: ${e2.message}`;
                    sendSSE({ type: 'agent_error', error: errMsg });
                    return errMsg;
                }
            } else {
                const errMsg = isSSLError(e)
                    ? '⚠️ Network/SSL Error: Connection interrupted. The agent will continue when connection is restored.'
                    : `⚠️ Agent Error: ${e.message}`;
                sendSSE({ type: 'agent_error', error: errMsg });
                return errMsg;
            }
        }

        if (aiResponse.content && aiResponse.toolCalls.length > 0) {
            sendSSE({ type: 'agent_reasoning', content: aiResponse.content, iteration: iter + 1 });
        }

        if (aiResponse.toolCalls.length > 0) {
            appendAssistantMessage(allMessages, aiResponse, provider);

            for (const tc of aiResponse.toolCalls) {
                sendSSE({ type: 'tool_call', id: tc.id, name: tc.name, args: tc.args });

                let result;
                let retries = 0;
                const MAX_RETRIES = 2;
                while (retries <= MAX_RETRIES) {
                    try {
                        result = executeTool(tc.name, tc.args);
                        if (result.success || retries >= MAX_RETRIES) break;
                        sendSSE({ type: 'tool_retry', id: tc.id, attempt: retries + 1, error: result.error });
                        retries++;
                    } catch (e) {
                        result = { success: false, error: e.message };
                        if (retries >= MAX_RETRIES) break;
                        retries++;
                    }
                }

                appendToolResult(allMessages, tc, result, provider);
                sendSSE({ type: 'tool_result', id: tc.id, name: tc.name, result });
            }
            continue;
        }

        if (aiResponse.content) {
            finalText = aiResponse.content;
            sendSSE({ type: 'agent_text', content: finalText });
        }
        break;
    }

    sendSSE({ type: 'done', fullText: finalText });
    return finalText;
}

// ─── AI Chat Proxy (existing simple chat — unchanged) ────────

async function streamChatResponse(messages, cfg, res) {
    const provider = cfg.AI_PROVIDER;
    const model = cfg.OPENAI_MODEL || cfg.AI_DISPLAY_MODEL;
    const baseUrl = cfg.OPENAI_BASE_URL || 'https://api.openai.com/v1';
    const apiKey = cfg.OPENAI_API_KEY || cfg.GEMINI_API_KEY || cfg.ANTHROPIC_API_KEY;

    res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
    });

    const sendSSE = (data) => res.write(`data: ${JSON.stringify(data)}\n\n`);

    // ── OpenAI-compatible (OpenRouter, Ollama, OpenAI) ────────
    if (provider === 'openai' || provider === 'ollama') {
        const body = JSON.stringify({ model, messages, max_tokens: 131072, stream: true });
        const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}`, 'Content-Length': Buffer.byteLength(body) };
        if (cfg.OPENAI_BASE_URL?.includes('openrouter')) {
            headers['HTTP-Referer'] = 'http://localhost:3000';
            headers['X-Title'] = 'Portable AI Dashboard';
        }
        let fullText = '';
        await streamExternal(`${baseUrl}/chat/completions`, headers, body,
            (chunk) => {
                chunk.split('\n').forEach(line => {
                    if (!line.startsWith('data: ')) return;
                    const raw = line.slice(6).trim();
                    if (raw === '[DONE]') return;
                    try {
                        const parsed = JSON.parse(raw);
                        const delta = parsed.choices?.[0]?.delta?.content || '';
                        if (delta) { fullText += delta; sendSSE({ type: 'delta', content: delta }); }
                    } catch {}
                });
            },
            () => { sendSSE({ type: 'done', fullText }); res.end(); }
        );
        return fullText;
    }

    // ── Anthropic ─────────────────────────────────────────────
    if (provider === 'anthropic') {
        const body = JSON.stringify({ model: model || 'claude-3-5-sonnet-20241022', messages, max_tokens: 131072, stream: true });
        const headers = { 'Content-Type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'Content-Length': Buffer.byteLength(body) };
        let fullText = '';
        await streamExternal('https://api.anthropic.com/v1/messages', headers, body,
            (chunk) => {
                chunk.split('\n').forEach(line => {
                    if (!line.startsWith('data: ')) return;
                    try {
                        const parsed = JSON.parse(line.slice(6));
                        const delta = parsed.delta?.text || '';
                        if (delta) { fullText += delta; sendSSE({ type: 'delta', content: delta }); }
                    } catch {}
                });
            },
            () => { sendSSE({ type: 'done', fullText }); res.end(); }
        );
        return fullText;
    }

    // ── Gemini ────────────────────────────────────────────────
    if (provider === 'gemini') {
        const gemModel = model || 'gemini-2.0-pro-exp-02-05';
        const gemMessages = messages.map(m => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }));
        const body = JSON.stringify({ contents: gemMessages });
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${gemModel}:streamGenerateContent?key=${apiKey}`;
        const headers = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) };
        let fullText = '';
        await streamExternal(url, headers, body,
            (chunk) => {
                try {
                    const matches = chunk.match(/"text":\s*"((?:[^"\\]|\\.)*)"/g) || [];
                    matches.forEach(m => {
                        const text = JSON.parse('{' + m + '}').text || '';
                        if (text) { fullText += text; sendSSE({ type: 'delta', content: text }); }
                    });
                } catch {}
            },
            () => { sendSSE({ type: 'done', fullText }); res.end(); }
        );
        return fullText;
    }

    sendSSE({ type: 'error', content: 'Provider not configured or unsupported.' });
    res.end();
    return '';
}

// ─── Server ──────────────────────────────────────────────────

const server = createServer(async (req, res) => {
    const url = new URL(req.url, `http://localhost:${PORT}`);

    if (req.method === 'OPTIONS') {
        res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' });
        return res.end();
    }

    try {
        if (url.pathname === '/' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            return res.end(readFileSync(HTML_FILE, 'utf-8'));
        }

        // Config
        if (url.pathname === '/api/config' && req.method === 'GET') return sendJSON(res, 200, readConfig());
        if (url.pathname === '/api/config' && req.method === 'POST') { const b = await readBody(req); writeConfig(b); return sendJSON(res, 200, { success: true }); }
        if (url.pathname === '/api/config/export' && req.method === 'GET') {
            if (!existsSync(ENV_FILE)) return sendJSON(res, 404, { error: 'No config' });
            res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Disposition': 'attachment; filename="ai_settings.env"' });
            return res.end(readFileSync(ENV_FILE, 'utf-8'));
        }
        if (url.pathname === '/api/config/import' && req.method === 'POST') { writeFileSync(ENV_FILE, await readBodyRaw(req), 'utf-8'); return sendJSON(res, 200, { success: true }); }

        // Models
        if (url.pathname === '/api/models' && req.method === 'GET') {
            const type = url.searchParams.get('type') || 'free';
            const result = await fetchExternal('https://openrouter.ai/api/v1/models');
            const parsed = JSON.parse(result.data);
            const models = (parsed.data || []).map(m => m.id).filter(id => type === 'free' ? id.endsWith(':free') : !id.endsWith(':free')).slice(0, 30);
            return sendJSON(res, 200, { models });
        }

        // NVIDIA NIM Models
        if (url.pathname === '/api/nvidia/models' && req.method === 'GET') {
            // NVIDIA NIM provides many models. We list the popular free/developer tier models here.
            const models = [
                'meta/llama-3.1-70b-instruct',
                'meta/llama-3.1-8b-instruct',
                'mistralai/mixtral-8x22b-instruct-v0.1',
                'mistralai/mixtral-8x7b-instruct-v0.1',
                'google/gemma-2-27b-it',
                'google/gemma-2-9b-it',
                'nvidia/nemotron-4-340b-instruct',
                'microsoft/phi-3-mini-128k-instruct'
            ];
            return sendJSON(res, 200, { models });
        }

        // DeepSeek Models
        if (url.pathname === '/api/deepseek/models' && req.method === 'POST') {
            const { key } = await readBody(req);
            const fallback = ['deepseek-v4-flash', 'deepseek-v4-pro'];
            try {
                const result = await fetchExternal('https://api.deepseek.com/models', { 'Authorization': `Bearer ${key}` });
                const parsed = JSON.parse(result.data);
                const models = (parsed.data || []).map(m => m.id).filter(Boolean);
                return sendJSON(res, 200, { models: models.length ? models : fallback });
            } catch {
                return sendJSON(res, 200, { models: fallback });
            }
        }

        // OpenAI-compatible Models
        if (url.pathname === '/api/openai-compatible/models' && req.method === 'POST') {
            const { baseUrl, key } = await readBody(req);
            if (!baseUrl) return sendJSON(res, 400, { models: [], error: 'Missing baseUrl' });
            const cleanBaseUrl = String(baseUrl).replace(/\/+$/, '');
            const apiKey = key || 'not-needed';
            try {
                const result = await fetchExternal(`${cleanBaseUrl}/models`, { 'Authorization': `Bearer ${apiKey}` });
                const parsed = JSON.parse(result.data);
                const models = (parsed.data || []).map(m => m.id).filter(Boolean);
                return sendJSON(res, 200, { models });
            } catch (e) {
                return sendJSON(res, 200, { models: [], error: e.message });
            }
        }

        // Verify Key
        if (url.pathname === '/api/verify-key' && req.method === 'POST') {
            const { provider, key, baseUrl } = await readBody(req);
            let valid = false;
            if (provider === 'openrouter') { const r = await fetchExternal('https://openrouter.ai/api/v1/auth/key', { 'Authorization': `Bearer ${key}` }); valid = r.status === 200; }
            else if (provider === 'nvidia') { const r = await fetchExternal('https://integrate.api.nvidia.com/v1/models', { 'Authorization': `Bearer ${key}` }); valid = r.status === 200; }
            else if (provider === 'deepseek') { const r = await fetchExternal('https://api.deepseek.com/models', { 'Authorization': `Bearer ${key}` }); valid = r.status === 200; }
            else if (provider === 'gemini') { const r = await fetchExternal(`https://generativelanguage.googleapis.com/v1beta/models?key=${key}`); valid = r.status === 200; }
            else if (provider === 'anthropic') { const r = await fetchExternal('https://api.anthropic.com/v1/models', { 'x-api-key': key, 'anthropic-version': '2023-06-01' }); valid = r.status === 200; }
            else if (provider === 'openai') { const r = await fetchExternal('https://api.openai.com/v1/models', { 'Authorization': `Bearer ${key}` }); valid = r.status === 200; }
            else if (provider === 'lmstudio') {
                try {
                    const cleanBaseUrl = String(baseUrl || 'http://localhost:1234/v1').replace(/\/+$/, '');
                    const r = await fetchExternal(`${cleanBaseUrl}/models`, { 'Authorization': 'Bearer lm-studio' });
                    valid = r.status === 200;
                } catch {
                    valid = false;
                }
            }
            else if (provider === 'custom-openai') {
                if (baseUrl) {
                    try {
                        const cleanBaseUrl = String(baseUrl).replace(/\/+$/, '');
                        const r = await fetchExternal(`${cleanBaseUrl}/models`, { 'Authorization': `Bearer ${key || 'not-needed'}` });
                        valid = r.status === 200;
                    } catch {
                        valid = false;
                    }
                }
            }
            else if (provider === 'ollama') {
                try { const r = await fetchExternal('http://127.0.0.1:11434/api/tags'); valid = r.status === 200; } catch { valid = false; }
            }
            return sendJSON(res, 200, { valid });
        }

        // Ollama Local Endpoints
        if (url.pathname === '/api/ollama/status' && req.method === 'GET') {
            const out = { installed: false, running: false };
            out.installed = existsSync(join(DATA_DIR, 'ollama', 'ollama.exe')) || existsSync(join(DATA_DIR, 'ollama', 'ollama'));
            try {
                const r = await fetchExternal('http://127.0.0.1:11434/api/tags');
                if (r.status === 200) out.running = true;
            } catch {}
            return sendJSON(res, 200, out);
        }

        if (url.pathname === '/api/ollama/models' && req.method === 'GET') {
            const models = [];
            const txtPath = join(DATA_DIR, 'models', 'installed-models.txt');
            if (existsSync(txtPath)) {
                try {
                    const lines = readFileSync(txtPath, 'utf8').split('\n').filter(Boolean);
                    for (const line of lines) {
                        const parts = line.split('|');
                        if (parts.length >= 1) {
                            models.push({ id: parts[0], name: parts[1] || parts[0], label: parts[2] || '' });
                        }
                    }
                } catch {}
            }
            try {
                const r = await fetchExternal('http://127.0.0.1:11434/api/tags');
                if (r.status === 200) {
                    const parsed = JSON.parse(r.data);
                    for (const m of (parsed.models || [])) {
                        if (!models.find(x => x.id === m.name)) models.push({ id: m.name, name: m.name, label: 'API' });
                    }
                }
            } catch {}
            return sendJSON(res, 200, { models });
        }

        if (url.pathname === '/api/ollama/start' && req.method === 'POST') {
            try {
                if (IS_WIN) {
                    const exe = join(DATA_DIR, 'ollama', 'ollama.exe');
                    if (existsSync(exe)) {
                        const env = { ...process.env, OLLAMA_MODELS: join(DATA_DIR, 'ollama', 'data') };
                        exec(`start "" /B /MIN "${exe}" serve`, { cwd: join(DATA_DIR, 'ollama'), env });
                        return sendJSON(res, 200, { success: true });
                    }
                } else {
                    const bin = join(DATA_DIR, 'ollama', 'ollama');
                    if (existsSync(bin)) {
                        const env = { ...process.env, OLLAMA_MODELS: join(DATA_DIR, 'ollama', 'data') };
                        exec(`"${bin}" serve > /dev/null 2>&1 &`, { cwd: join(DATA_DIR, 'ollama'), env });
                        return sendJSON(res, 200, { success: true });
                    }
                }
                return sendJSON(res, 404, { error: 'Ollama not installed' });
            } catch (e) {
                return sendJSON(res, 500, { error: e.message });
            }
        }

        if (url.pathname === '/api/ollama/stop' && req.method === 'POST') {
            try {
                if (IS_WIN) execSync('taskkill /F /IM ollama.exe', { stdio: 'ignore' });
                else execSync('pkill -f "ollama serve"', { stdio: 'ignore' });
                return sendJSON(res, 200, { success: true });
            } catch (e) {
                return sendJSON(res, 500, { error: e.message });
            }
        }

        // Health
        if (url.pathname === '/api/health' && req.method === 'GET') {
            return sendJSON(res, 200, {
                status: 'ok',
                version: '1.1.0',
                uptime: process.uptime(),
                platform: process.platform,
                arch: process.arch,
                nodeVersion: process.version,
                configExists: existsSync(ENV_FILE),
                ollamaInstalled: existsSync(join(DATA_DIR, 'ollama', 'ollama')) || existsSync(join(DATA_DIR, 'ollama', 'ollama.exe')),
            });
        }

        // System
        if (url.pathname === '/api/system' && req.method === 'GET') return sendJSON(res, 200, getSystemInfo());

        // Logs
        if (url.pathname === '/api/logs' && req.method === 'GET') return sendJSON(res, 200, { logs: getSessionLogs() });
        if (url.pathname === '/api/logs/read' && req.method === 'GET') {
            const filePath = join(ROOT_DIR, url.searchParams.get('path') || '');
            if (!existsSync(filePath)) return sendJSON(res, 404, { error: 'Not found' });
            return sendJSON(res, 200, { content: readFileSync(filePath, 'utf-8').slice(0, 10000) });
        }

        // Updates
        if (url.pathname === '/api/updates' && req.method === 'GET') {
            const current = getInstalledVersion(), latest = getLatestVersion();
            return sendJSON(res, 200, { current: current || 'unknown', latest: latest || 'unknown', updateAvailable: current && latest && current !== latest });
        }
        if (url.pathname === '/api/updates/install' && req.method === 'POST') {
            try {
                const npm = join(BIN_DIR, IS_WIN ? 'npm.cmd' : 'npm');
                const cwd = join(ROOT_DIR, 'engine');
                const cache = join(DATA_DIR, 'npm-cache');
                if (!existsSync(cache)) mkdirSync(cache, { recursive: true });
                // Clear old install and fresh install to ensure version bump
                const oldDir = join(cwd, 'node_modules', '@gitlawb', 'openclaude');
                if (existsSync(oldDir)) { rmSync(oldDir, { recursive: true, force: true }); }
                const result = execSync(`"${npm}" install @gitlawb/openclaude@latest --no-audit --no-fund --no-bin-links --cache "${cache}"`, {
                    cwd, encoding: 'utf-8', timeout: 300000, stdio: ['pipe', 'pipe', 'pipe']
                });
                return sendJSON(res, 200, { success: true, version: getInstalledVersion(), output: result.slice(0, 2000) });
            } catch (e) {
                const stderr = e.stderr || e.message || 'Unknown error';
                return sendJSON(res, 500, { error: stderr.slice(0, 2000) });
            }
        }

        // Launch (always limitless)
        if (url.pathname === '/api/launch' && req.method === 'POST') {
            const startScript = join(ROOT_DIR, IS_WIN ? 'START.bat' : 'start.sh');
            if (IS_WIN) {
                exec(`start "" /B cmd /c "${startScript}" --quick`);
            } else {
                exec(`bash "${startScript}" --quick > /dev/null 2>&1 &`);
            }
            return sendJSON(res, 200, { success: true });
        }

        // ── Working Directory ────────────────────────────────
        if (url.pathname === '/api/workdir' && req.method === 'GET') {
            return sendJSON(res, 200, { workDir: WORK_DIR });
        }
        if (url.pathname === '/api/workdir' && req.method === 'POST') {
            const { path } = await readBody(req);
            const abs = resolve(path);
            if (!existsSync(abs)) return sendJSON(res, 400, { error: 'Directory does not exist' });
            WORK_DIR = abs;
            return sendJSON(res, 200, { success: true, workDir: WORK_DIR });
        }

        // ── Chat History ──────────────────────────────────────
        if (url.pathname === '/api/chats' && req.method === 'GET') return sendJSON(res, 200, { chats: listChats() });

        if (url.pathname === '/api/chats' && req.method === 'POST') {
            const { title } = await readBody(req);
            const id = newChatId();
            const now = new Date().toISOString();
            saveChat(id, { id, title: title || 'New Conversation', created: now, updated: now, messages: [] });
            return sendJSON(res, 200, { id });
        }

        const chatMatch = url.pathname.match(/^\/api\/chats\/([^/]+)$/);
        if (chatMatch) {
            const chatId = chatMatch[1];
            if (req.method === 'GET') {
                const chat = loadChat(chatId);
                return chat ? sendJSON(res, 200, chat) : sendJSON(res, 404, { error: 'Chat not found' });
            }
            if (req.method === 'DELETE') {
                const file = join(CHATS_DIR, `${chatId}.json`);
                if (existsSync(file)) { unlinkSync(file); }
                return sendJSON(res, 200, { success: true });
            }
            if (req.method === 'POST') {
                const data = await readBody(req);
                saveChat(chatId, data);
                return sendJSON(res, 200, { success: true });
            }
        }

        // ── Agent Endpoint (always limitless) ────────────────
        if (url.pathname === '/api/agent' && req.method === 'POST') {
            const { chatId, messages, userMessage } = await readBody(req);
            const cfg = readConfig();

            res.writeHead(200, {
                'Content-Type': 'text/event-stream',
                'Cache-Control': 'no-cache',
                'Connection': 'keep-alive',
                'Access-Control-Allow-Origin': '*',
            });

            const sendSSE = (data) => { try { res.write(`data: ${JSON.stringify(data)}\n\n`); } catch {} };

            if (!cfg.AI_PROVIDER) {
                sendSSE({ type: 'agent_error', error: 'No AI provider configured. Please complete setup first.' });
                return res.end();
            }

            const history = messages || [];
            const allMessages = [...history, { role: 'user', content: userMessage }];

            try {
                const fullText = await runAgent(allMessages, cfg, sendSSE);

                if (chatId && fullText) {
                    const existing = loadChat(chatId) || { id: chatId, title: userMessage.slice(0, 50), created: new Date().toISOString(), messages: [] };
                    existing.messages.push({ role: 'user', content: userMessage }, { role: 'assistant', content: fullText });
                    existing.updated = new Date().toISOString();
                    if (!existing.title || existing.title === 'New Conversation') existing.title = userMessage.slice(0, 50);
                    saveChat(chatId, existing);
                }
            } catch (e) {
                const errText = `⚠️ Agent Error: ${e.message}`;
                sendSSE({ type: 'agent_error', error: e.message });
                if (chatId) {
                    const existing = loadChat(chatId) || { id: chatId, title: userMessage.slice(0, 50), created: new Date().toISOString(), messages: [] };
                    existing.messages.push({ role: 'user', content: userMessage }, { role: 'assistant', content: errText });
                    existing.updated = new Date().toISOString();
                    if (!existing.title || existing.title === 'New Conversation') existing.title = userMessage.slice(0, 50);
                    saveChat(chatId, existing);
                }
            }
            return res.end();
        }

        // ── Chat Stream (always limitless) ────────────────────
        if (url.pathname === '/api/chat' && req.method === 'POST') {
            const { chatId, messages, userMessage } = await readBody(req);
            const cfg = readConfig();

            if (!cfg.AI_PROVIDER) {
                res.writeHead(400, { 'Content-Type': 'text/event-stream', 'Access-Control-Allow-Origin': '*' });
                res.write(`data: ${JSON.stringify({ type: 'error', content: 'No AI provider configured. Please complete setup first.' })}\n\n`);
                return res.end();
            }

            const sysContent = 'You are an autonomous AI coding assistant with full tool access. Execute tasks directly and completely without asking for confirmation. Make reasonable assumptions and proceed immediately with complete results. Never stop until the task is fully done.';
            const history = messages || [];
            const allMessages = [
                ...(history.length === 0 ? [{ role: 'user', content: `[System Instructions: ${sysContent}]` }] : []),
                ...history,
                { role: 'user', content: userMessage },
            ];
            const fullText = await streamChatResponse(allMessages, cfg, res);

            if (chatId && fullText) {
                const existing = loadChat(chatId) || { id: chatId, title: userMessage.slice(0, 50), created: new Date().toISOString(), messages: [] };
                existing.messages.push({ role: 'user', content: userMessage }, { role: 'assistant', content: fullText });
                existing.updated = new Date().toISOString();
                if (!existing.title || existing.title === 'New Conversation') existing.title = userMessage.slice(0, 50);
                saveChat(chatId, existing);
            }
            return;
        }

        sendJSON(res, 404, { error: 'Not found' });

    } catch (err) {
        console.error(err);
        try { sendJSON(res, 500, { error: err.message }); } catch {}
    }
});

server.listen(PORT, () => {
    console.log(`\n  Dashboard running at http://localhost:${PORT}`);
    console.log(`  Agent working directory: ${WORK_DIR}`);
    console.log('  Press Ctrl+C to stop.\n');
});
