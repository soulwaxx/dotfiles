import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const [source, hook, middleware] = process.argv.slice(2);
if (!source || !hook || !middleware) throw new Error("extension, hook, and middleware paths required");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "obsidian-extension-"));
try {
  const vault = path.join(tmp, "vault");
  fs.mkdirSync(path.join(vault, "wiki", "topic"), { recursive: true });
  fs.mkdirSync(path.join(vault, "wiki", ".raw"));
  fs.mkdirSync(path.join(tmp, "agent", "extensions", "dotfiles-obsidian"), { recursive: true });
  fs.writeFileSync(path.join(tmp, "agent", "extensions", "dotfiles-obsidian", "config.json"),
    JSON.stringify({ hookPath: hook, vaultPath: vault }));
  const importLine = 'import { getAgentDir, type ExtensionAPI } from "@earendil-works/pi-coding-agent";';
  const text = fs.readFileSync(source, "utf8");
  assert.ok(text.includes(importLine));
  fs.writeFileSync(path.join(tmp, "extension.ts"), text.replace(importLine,
    'const getAgentDir = () => process.env.TEST_AGENT_DIR; type ExtensionAPI = unknown;'));
  process.env.TEST_AGENT_DIR = path.join(tmp, "agent");
  process.env.WIKI_MIDDLEWARE_DIR = middleware;
  const handlers = new Map();
  const { default: extension } = await import(pathToFileURL(path.join(tmp, "extension.ts")));
  extension({ on: (event, handler) => handlers.set(event, handler) });
  const ctx = { cwd: vault };
  const call = (p, toolName = "write") => handlers.get("tool_call")({ toolName, input: { path: p } }, ctx);
  assert.equal(await call("wiki/topic/page.md"), undefined);
  assert.equal(await call("outside.md"), undefined);
  for (const p of ["wiki/index.md", "wiki/topic/index.md", "wiki/log.md", "wiki/.raw/secret.env"]) {
    assert.equal((await call(p))?.block, true, `expected block: ${p}`);
  }
  fs.symlinkSync(path.join(vault, "wiki", "topic"), path.join(vault, "wiki", "alias"));
  assert.equal((await call("wiki/alias/page.md", "edit"))?.block, true);
  assert.equal((await call("wiki/topic/page.md", "bash")), undefined);
  console.log("pi Obsidian pre-write checks PASS");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
