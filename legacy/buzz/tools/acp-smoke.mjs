#!/usr/bin/env node
// Minimal ACP (v1) smoke client. Usage:
//   node acp-smoke.mjs --cwd DIR --prompt "text" [--meta '{json}'] [--mode MODE] [--set configId=value]... -- <command> [args...]
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const argv = process.argv.slice(2);
const sep = argv.indexOf("--");
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 && i < sep ? argv[i + 1] : d; };
const cwd = opt("--cwd", process.cwd());
const promptText = opt("--prompt", "Say hello.");
const meta = JSON.parse(opt("--meta", "null"));
const [cmd, ...args] = argv.slice(sep + 1);
if (!cmd) { console.error("need -- <command>"); process.exit(2); }

const child = spawn(cmd, args, { stdio: ["pipe", "pipe", "inherit"], env: process.env });
let nextId = 1; const pending = new Map();
const send = (m) => child.stdin.write(JSON.stringify(m) + "\n");
const call = (method, params) => new Promise((res, rej) => {
  const id = nextId++; pending.set(id, { res, rej }); send({ jsonrpc: "2.0", id, method, params });
});
const log = (tag, o) => console.log(`[${tag}] ${typeof o === "string" ? o : JSON.stringify(o)}`);

let buf = "";
child.stdout.on("data", (d) => {
  buf += d; const lines = buf.split("\n"); buf = lines.pop();
  for (const line of lines) if (line.trim()) onMsg(JSON.parse(line));
});
child.on("exit", (c) => { log("exit", `agent exited ${c}`); process.exit(c ?? 1); });

function onMsg(m) {
  if (m.id !== undefined && m.method === undefined) {           // response
    const p = pending.get(m.id); pending.delete(m.id);
    m.error ? p.rej(new Error(JSON.stringify(m.error))) : p.res(m.result);
  } else if (m.method === "session/update") {                   // notification
    const u = m.params.update;
    if (u.sessionUpdate === "agent_message_chunk" && u.content?.type === "text") process.stdout.write(u.content.text);
    else if (u.sessionUpdate === "available_commands_update") log(u.sessionUpdate, u.availableCommands.map((c) => c.name).join(" "));
    else log(u.sessionUpdate, u.title ?? u.content?.text ?? u.status ?? u.currentModeId ?? "");
  } else if (m.method === "session/request_permission") {       // auto-allow
    const opts = m.params.options ?? [];
    const pick = opts.find((o) => o.kind === "allow_always") ?? opts.find((o) => o.kind === "allow_once") ?? opts[0];
    log("permission", `${m.params.toolCall?.title} -> ${pick?.optionId}`);
    send({ jsonrpc: "2.0", id: m.id, result: { outcome: { outcome: "selected", optionId: pick?.optionId } } });
  } else if (m.method === "fs/read_text_file") {
    try { send({ jsonrpc: "2.0", id: m.id, result: { content: readFileSync(m.params.path, "utf8") } }); }
    catch (e) { send({ jsonrpc: "2.0", id: m.id, error: { code: -32603, message: String(e) } }); }
  } else if (m.method === "fs/write_text_file") {
    writeFileSync(m.params.path, m.params.content); send({ jsonrpc: "2.0", id: m.id, result: {} });
  } else if (m.id !== undefined) {                              // unknown request
    send({ jsonrpc: "2.0", id: m.id, error: { code: -32601, message: `unsupported: ${m.method}` } });
  } else log(m.method ?? "notif", m.params ?? "");
}

const init = await call("initialize", {
  protocolVersion: 1,
  clientCapabilities: { fs: { readTextFile: true, writeTextFile: true }, terminal: false },
  clientInfo: { name: "acp-smoke", version: "0" },
});
log("initialize", { agent: init.agentInfo, auth: init.authMethods?.map((a) => a.id) });
const sess = await call("session/new", { cwd, mcpServers: [], ...(meta ? { _meta: meta } : {}) });
log("session/new", { sessionId: sess.sessionId, modes: sess.modes?.availableModes?.map((x) => x.id), currentMode: sess.modes?.currentModeId, models: sess.models?.availableModels?.map((x) => x.modelId ?? x.id), currentModel: sess.models?.currentModelId });
const modeId = opt("--mode");                                   // --mode bypassPermissions
if (modeId) log("set_mode", await call("session/set_mode", { sessionId: sess.sessionId, modeId }));
for (const kv of argv.slice(0, sep).flatMap((a, i) => (a === "--set" ? [argv[i + 1]] : []))) {   // --set configId=value
  const [configId, value] = kv.split("="); log("set_config_option", await call("session/set_config_option", { sessionId: sess.sessionId, configId, value }));
}
const res = await call("session/prompt", { sessionId: sess.sessionId, prompt: [{ type: "text", text: promptText }] });
console.log(); log("session/prompt", res);
child.kill(); process.exit(0);
