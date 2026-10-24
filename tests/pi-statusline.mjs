import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, readlinkSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createContext, SourceTextModule, SyntheticModule } from "node:vm";
import test from "node:test";

const source = readFileSync(process.argv[2], "utf8");
const strip = (text) => text.replace(/\x1b\[[0-9;]*m/g, "");
// Only the host's terminal-width helpers are mocked in the dependency-free
// flake check. Pass a pi-tui entrypoint as argv[3] to run against the real ones.
const width = (text) => [...strip(text)].reduce((n, char) =>
  n + (/\p{Mark}/u.test(char) ? 0 : /[\u4e00-\u9fff]|\p{Extended_Pictographic}/u.test(char) ? 2 : 1), 0);
const truncate = (text, columns, ellipsis = "…") => {
  if (width(text) <= columns) return text;
  const suffix = columns >= width(ellipsis) ? ellipsis : "";
  let result = "";
  for (const char of strip(text)) {
    if (width(result + char + suffix) > columns) break;
    result += char;
  }
  return result + suffix;
};
const tui = process.argv[3] ? await import(pathToFileURL(resolve(process.argv[3])).href)
  : { visibleWidth: width, truncateToWidth: truncate };

async function load(options = {}) {
  const context = createContext({
    AbortController, setInterval: options.setInterval ?? setInterval,
    clearInterval: options.clearInterval ?? clearInterval,
  });
  const module = new SourceTextModule(source, { context });
  await module.link(async (specifier) => {
    let exports;
    if (specifier === "@earendil-works/pi-tui") exports = tui;
    else if (specifier === "node:child_process" && options.execFile) exports = { execFile: options.execFile };
    else exports = await import(specifier);
    return new SyntheticModule(Object.keys(exports), function () {
      for (const [key, value] of Object.entries(exports)) this.setExport(key, value);
    }, { context });
  });
  await module.evaluate();
  return module.namespace;
}
if (process.env.PI_STATUSLINE_FIXTURES) {
  test("generated host settings remove Powerline and link the custom extension", () => {
    const fixtures = JSON.parse(readFileSync(process.env.PI_STATUSLINE_FIXTURES, "utf8"));
    assert.ok(Object.keys(fixtures).length > 0);
    for (const [hostname, fixture] of Object.entries(fixtures)) {
      const settings = JSON.parse(readFileSync(fixture.settings, "utf8"));
      const sources = settings.packages.map((pkg) => typeof pkg === "string" ? pkg : pkg.source);
      assert.ok(!sources.includes("npm:pi-powerline-footer"), hostname);
      assert.ok(!("powerline" in settings) && !("powerlineShortcuts" in settings), hostname);
      assert.ok(readlinkSync(fixture.extension).endsWith("/config/pi/statusline"), hostname);
    }
  });
}
const footer = await load();
const theme = { fg: (color, text) => `\x1b[${({ error: 31, warning: 33, accent: 35 })[color] ?? 37}m${text}\x1b[0m` };
const model = { provider: "test", id: "sol", name: "GPT-6.1 Sol", contextWindow: 272000, cost: { input: 1, output: 2 } };
const registry = { find: () => model };
const usage = (cost = 0.11) => ({ input: 41000, output: 500, cacheRead: 138000, cacheWrite: 0, cost: { total: cost } });
const assistant = (cost = 0.11) => ({ type: "message", message: { role: "assistant", provider: "test", model: "sol", usage: usage(cost) } });
const state = () => ({
  cwd: "/home/test/dotfiles", model, thinking: "high", autoCompact: true,
  git: { branch: "main", staged: 0, unstaged: 1, untracked: 0 },
  context: { tokens: 30736, contextWindow: 272000, percent: 11.3 },
  usage: footer.sessionUsage([assistant()], registry),
});
const render = (s = state(), columns = 200, statuses = new Map()) => footer.renderStatusline(columns, theme, s, statuses);
const plain = (lines) => Array.from(lines, strip);

test("full layout preserves order, icons, middle dots, and reported values", () => {
  assert.deepEqual(plain(render()), [" GPT-6.1 Sol · think:high ·  dotfiles ·  main *1 ·  31k/272k (11.3%) 󰁨 ·   138k (77%) · $0.11"]);
  const s = state();
  s.git.staged = 2;
  s.git.untracked = 3;
  assert.ok(plain(render(s))[0].includes("main +2 *1 ?3"));
  s.usage.cacheRead = 0;
  s.git = undefined;
  s.autoCompact = false;
  const line = plain(render(s))[0];
  assert.ok(!line.includes("") && !line.includes("") && !line.includes("󰁨"));
  assert.equal(line.split(" · ").length, 5);
});

test("compact layout keeps only model, branch, context percentage, and cost", () => {
  const line = plain(render(state(), 65))[0];
  assert.equal(line, " GPT-6.1 Sol ·  main ·  11.3% 󰁨 · $0.11");
  assert.ok(!line.includes("think:") && !line.includes("dotfiles") && !line.includes("*1"));
  for (let columns = 0; columns <= 200; columns++) {
    const s = state();
    s.model = { ...model, name: "模型😀é".repeat(20) };
    s.git.branch = "feature/模型😀é".repeat(10);
    for (const line of render(s, columns)) assert.ok(tui.visibleWidth(line) <= columns, `${columns}: ${strip(line)}`);
  }
  const narrow = plain(render(state(), 45))[0];
  assert.ok(narrow.includes("11.3%") && narrow.includes("$0.11") && narrow.includes("main"));
});

test("context uses native values, strict thresholds, unknown state, and compaction flag", () => {
  const s = state();
  for (const [percent, ansi] of [[70, 37], [70.1, 33], [90, 33], [90.1, 31]]) {
    s.context.percent = percent;
    assert.ok(render(s)[0].includes(`\x1b[${ansi}m 31k/272k (${percent.toFixed(1)}%)`));
  }
  s.context = { tokens: null, percent: null, contextWindow: 272000 };
  assert.ok(plain(render(s))[0].includes("?/272k"));
  s.context = undefined;
  assert.ok(plain(render(s))[0].includes("?/272k"));
  s.model = undefined;
  assert.ok(plain(render(s))[0].includes("no-model") && plain(render(s))[0].includes("?/?"));
});

test("extension statuses retain ANSI colors, have a conditional single row, and cannot wrap", () => {
  const statuses = new Map([["task", "\x1b[32mworking\x1b[0m"], ["agent", "scout\nready"]]);
  const lines = render(state(), 200, statuses);
  assert.equal(lines.length, 2);
  assert.equal(strip(lines[1]), "working · scout ready");
  assert.ok(lines[1].includes("\x1b[32mworking\x1b[0m"));
  assert.equal(render(state(), 200, new Map([["empty", " "]])).length, 1);
  assert.ok(tui.visibleWidth(render(state(), 10, statuses)[1]) <= 10);
  const s = state();
  s.cwd = "/tmp/bad\n\x1b[31mname";
  assert.ok(!plain(render(s))[0].includes("\n"));
});

test("full-ledger accounting includes branches, summaries, compaction, tools, and usage notices", () => {
  const entries = [assistant(1), assistant(2), { type: "compaction", usage: usage(3) },
    { type: "branch_summary", usage: usage(4) }, { type: "usage", provider: "test", model: "sol", usage: usage(5) },
    { type: "message", message: { role: "toolResult", toolName: "subagent", usage: usage(6), details: { results: [{ usage: { cost: 999 } }] } } }];
  const totals = footer.sessionUsage(entries, registry);
  assert.equal(totals.cost, 21);
  assert.equal(totals.input, 6 * 41000);
  assert.equal(totals.cacheRead, 6 * 138000);
  assert.equal(totals.unknownCost, false);
});

test("legacy subagent details are counted only when native usage is absent", () => {
  const result = { results: [{ usage: { input: 10, cacheRead: 30, cost: 1.5 } }] };
  const entries = [
    { type: "message", message: { role: "toolResult", toolName: "subagent", details: result } },
    { type: "custom_message", customType: "subagent-slash-result", details: { result: { details: result } } },
  ];
  assert.equal(footer.sessionUsage(entries, registry).cost, 3);
  assert.equal(footer.sessionUsage(entries, registry).cacheRead, 60);
});

test("missing or zero unknown pricing is n/a rather than a false zero", () => {
  const s = state();
  s.model = { ...model, cost: { input: 0, output: 0 } };
  s.usage = footer.sessionUsage([assistant(0)], { find: () => s.model });
  assert.ok(plain(render(s))[0].endsWith(" · n/a"));
  assert.equal(s.usage.unknownCost, true);
  s.usage = footer.sessionUsage([], registry);
  assert.ok(plain(render(s))[0].endsWith(" · n/a"));
  s.model = model;
  assert.ok(plain(render(s))[0].endsWith(" · $0.00"));
  const missing = assistant();
  delete missing.message.usage.cost;
  assert.equal(footer.sessionUsage([missing], registry).unknownCost, true);
});

test("porcelain parsing handles counts, renames, copies, conflicts, and unborn branches", () => {
  const parsed = footer.parseGitStatus("## main...origin/main [ahead 1]\0M  staged\0 M unstaged\0MM both\0?? new\0R  renamed\0old\0UU conflict\0");
  assert.equal(parsed.branch, "main");
  assert.equal(parsed.staged, 4);
  assert.equal(parsed.unstaged, 3);
  assert.equal(parsed.untracked, 1);
  assert.equal(footer.parseGitStatus("## No commits yet on trunk\0").branch, "trunk");
  assert.equal(footer.parseGitStatus("## HEAD (no branch)\0").detached, true);
  assert.equal(footer.parseGitStatus(""), undefined);
});

test("asynchronous Git works in repositories, detached HEAD, subdirectories, and non-repositories", async () => {
  const dir = mkdtempSync(join(tmpdir(), "pi-statusline-"));
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { encoding: "utf8" }).trim();
  try {
    assert.equal(await footer.readGit(dir), undefined);
    git("init", "-q", "-b", "main");
    writeFileSync(join(dir, "tracked"), "initial");
    git("add", ".");
    git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "commit", "-qm", "initial");
    writeFileSync(join(dir, "tracked"), "changed");
    writeFileSync(join(dir, "new"), "untracked");
    const status = await footer.readGit(dir);
    assert.equal(status.branch, "main");
    assert.equal(status.unstaged, 1);
    assert.equal(status.untracked, 1);
    const subdir = mkdtempSync(join(dir, "subdir-"));
    assert.equal((await footer.readGit(subdir)).branch, "main");
    git("checkout", "--detach", "-q");
    assert.equal((await footer.readGit(dir)).branch, git("rev-parse", "--short", "HEAD"));
    const controller = new AbortController();
    controller.abort();
    assert.equal(await footer.readGit(dir, controller.signal), undefined);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("TUI lifecycle refreshes cached snapshots and disposes resources on reload and shutdown", async () => {
  const handlers = new Map();
  let component, scans = 0, renders = 0, unsubscribed = 0, pendingCallback, pendingSignal;
  let entries = [assistant(1)], leaf = "a", session = "first";
  const timers = new Set();
  const api = {
    on: (name, handler) => handlers.set(name, handler),
    getThinkingLevel: () => "high",
    getSettings: () => ({ compaction: { enabled: false } }),
  };
  const host = {
    requestRender: () => renders++,
  };
  const data = {
    onBranchChange: () => () => unsubscribed++,
    getExtensionStatuses: () => new Map(),
  };
  const ctx = {
    mode: "tui", cwd: "/tmp", model, modelRegistry: registry,
    getContextUsage: () => ({ tokens: 100, percent: 1, contextWindow: 272000 }),
    sessionManager: {
      getEntries: () => { scans++; return entries; }, getLeafId: () => leaf, getSessionId: () => session,
    },
    ui: { setFooter: (factory) => { component?.dispose(); component = factory(host, theme, data); } },
  };
  const extension = await load({
    execFile: (_cmd, _args, options, callback) => {
      pendingCallback = callback; pendingSignal = options.signal;
    },
    setInterval: (callback, ms) => {
      assert.equal(ms, 2000);
      const timer = { callback, unref() {} };
      timers.add(timer);
      return timer;
    },
    clearInterval: (timer) => timers.delete(timer),
  });
  extension.default(api);
  handlers.get("session_start")({}, { ...ctx, mode: "rpc" });
  assert.equal(component, undefined);
  handlers.get("session_start")({}, ctx);
  pendingCallback(null, "## main\0");
  await new Promise(setImmediate);
  assert.ok(plain(component.render(200))[0].endsWith("$1.00"));
  component.render(200);
  assert.equal(scans, 1, "typing does not scan the ledger again");
  const refreshing = [...timers][0].callback();
  pendingCallback(null, "## main\0");
  await refreshing;
  component.render(200);
  assert.equal(scans, 2, "idle refresh picks up usage notices and external Git changes");
  entries.push({ type: "compaction", usage: usage(2) });
  handlers.get("session_compact")({}, ctx);
  assert.ok(plain(component.render(200))[0].endsWith("$3.00"));
  leaf = "earlier-branch";
  handlers.get("session_tree")({}, ctx);
  assert.ok(plain(component.render(200))[0].endsWith("$3.00"));
  session = "second";
  entries = [];
  component.invalidate();
  assert.ok(plain(component.render(200))[0].endsWith("$0.00"));
  assert.ok(!plain(component.render(200))[0].includes("󰁨"));
  assert.ok(renders >= 3);
  handlers.get("session_start")({}, ctx);
  assert.equal(unsubscribed, 1, "replacement disposes old resources once");
  const rendersBeforeShutdown = renders;
  handlers.get("session_shutdown")({}, ctx);
  handlers.get("session_shutdown")({}, ctx);
  component.dispose();
  assert.equal(unsubscribed, 2);
  assert.equal(timers.size, 0);
  assert.equal(pendingSignal.aborted, true);
  pendingCallback(null, "## stale\0");
  await new Promise(setImmediate);
  assert.equal(renders, rendersBeforeShutdown, "in-flight Git completion cannot render a disposed footer");
});
