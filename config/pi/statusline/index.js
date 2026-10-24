import { execFile } from "node:child_process";
import { basename } from "node:path";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const clean = (text) => String(text).replace(/[\x00-\x1f\x7f-\x9f]/g, " ");
const priced = (model) => Object.values(model?.cost ?? {}).some((rate) => rate > 0);

export function formatTokens(count) {
  if (count < 1000) return String(count);
  if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
  if (count < 1000000) return `${Math.round(count / 1000)}k`;
  return `${Number((count / 1000000).toFixed(1))}M`;
}

// Read the entire ledger, not the active branch or compacted context. Native
// tool usage already includes child costs; details are a legacy-only fallback.
export function sessionUsage(entries, registry) {
  const totals = { input: 0, cacheRead: 0, cost: 0, unknownCost: false };
  const add = (usage, model) => {
    const input = usage.input ?? 0;
    const output = usage.output ?? 0;
    const cacheRead = usage.cacheRead ?? 0;
    const cacheWrite = usage.cacheWrite ?? 0;
    const cost = typeof usage.cost === "number" ? usage.cost : usage.cost?.total;
    totals.input += input;
    totals.cacheRead += cacheRead;
    if (Number.isFinite(cost) && cost >= 0) totals.cost += cost;
    if (!Number.isFinite(cost) || cost < 0 ||
        (cost === 0 && input + output + cacheRead + cacheWrite > 0 && !priced(model))) {
      totals.unknownCost = true;
    }
  };
  for (const entry of entries) {
    const message = entry.type === "message" ? entry.message : undefined;
    const usage = message?.role === "assistant" || message?.role === "toolResult"
      ? message.usage
      : ["usage", "compaction", "branch_summary"].includes(entry.type) ? entry.usage : undefined;
    if (usage) {
      const provider = message?.provider ?? entry.provider;
      const modelId = message?.responseModel ?? message?.model ?? entry.model;
      add(usage, provider && modelId ? registry.find(provider, modelId) : undefined);
      continue;
    }
    const details = message?.role === "toolResult" && message.toolName === "subagent"
      ? message.details
      : entry.type === "custom_message" && entry.customType === "subagent-slash-result"
        ? entry.details?.result?.details : undefined;
    for (const result of details?.results ?? []) {
      if (result.usage) add(result.usage);
    }
    if (message?.role === "assistant") totals.unknownCost = true;
  }
  return totals;
}

export function parseGitStatus(output) {
  const [header, ...records] = output.split("\0");
  if (!header.startsWith("## ")) return undefined;
  let branch = header.slice(3).split("...")[0];
  branch = branch.replace(/^(No commits yet on|Initial commit on) /, "");
  const detached = branch === "HEAD (no branch)";
  let staged = 0, unstaged = 0, untracked = 0;
  for (let i = 0; i < records.length; i++) {
    const record = records[i];
    if (!record) continue;
    if (record.startsWith("??")) untracked++;
    else if (!record.startsWith("!!")) {
      if (record[0] !== " ") staged++;
      if (record[1] !== " ") unstaged++;
      // Porcelain -z stores the source name of a rename/copy in the next record.
      if (/[RC]/.test(record.slice(0, 2))) i++;
    }
  }
  return { branch, detached, staged, unstaged, untracked };
}

export async function readGit(cwd, signal) {
  const run = (args) => new Promise((resolve, reject) => {
    execFile("git", ["--no-optional-locks", ...args], {
      cwd, signal, timeout: 2000, maxBuffer: 4 * 1024 * 1024,
    }, (error, stdout) => error ? reject(error) : resolve(stdout));
  });
  try {
    const status = parseGitStatus(await run(["status", "--porcelain=v1", "--branch", "-z", "--untracked-files=all"]));
    if (status?.detached) status.branch = (await run(["rev-parse", "--short", "HEAD"])).trim();
    return status;
  } catch {
    // Not a repository, Git unavailable, or a timed-out/cancelled status read.
    return undefined;
  }
}

export function renderStatusline(width, theme, state, statuses) {
  const fg = (color, text) => theme.fg(color, text);
  const separator = fg("dim", " · ");
  const join = (parts) => parts.filter(Boolean).join(separator);
  const { model, usage, context, git } = state;
  const modelName = clean(model?.name ?? model?.id ?? "no-model");
  const branch = git ? clean(git.branch) : undefined;
  const percent = context?.percent;
  const contextColor = percent > 90 ? "error" : percent > 70 ? "warning" : "muted";
  const auto = state.autoCompact ? " 󰁨" : "";
  const window = context?.contextWindow ?? model?.contextWindow;
  const contextText = context?.tokens != null && percent != null
    ? `${formatTokens(context.tokens)}/${window ? formatTokens(window) : "?"} (${percent.toFixed(1)}%)`
    : `?/${window ? formatTokens(window) : "?"}`;
  const cost = fg("muted", usage.unknownCost || (usage.cost === 0 && !priced(model)) ? "n/a" : `$${usage.cost.toFixed(2)}`);
  const gitCounts = git ? [git.staged && `+${git.staged}`, git.unstaged && `*${git.unstaged}`, git.untracked && `?${git.untracked}`].filter(Boolean).join(" ") : "";
  const cache = usage.cacheRead > 0
    ? fg("dim", `  ${formatTokens(usage.cacheRead)} (${Math.round(100 * usage.cacheRead / (usage.input + usage.cacheRead))}%)`)
    : undefined;
  let row = join([
    fg("accent", ` ${modelName}`),
    fg(`thinking${state.thinking[0].toUpperCase()}${state.thinking.slice(1)}`, `think:${state.thinking}`),
    fg("muted", ` ${clean(basename(state.cwd) || state.cwd)}`),
    branch && fg(gitCounts ? "warning" : "success", ` ${branch}${gitCounts ? ` ${gitCounts}` : ""}`),
    fg(contextColor, ` ${contextText}${auto}`), cache, cost,
  ]);
  if (visibleWidth(row) > width) {
    const compactContext = fg(contextColor, ` ${percent == null ? "?" : `${percent.toFixed(1)}%`}${auto}`);
    const fixed = visibleWidth(join([" ", branch && " ", compactContext, cost]));
    const budget = Math.max(0, width - fixed);
    const branchBudget = branch ? Math.min(visibleWidth(branch), Math.floor(budget / 2)) : 0;
    const shortModel = truncateToWidth(modelName, budget - branchBudget, "…");
    const shortBranch = branch && truncateToWidth(branch, branchBudget, "…");
    row = join([
      fg("accent", ` ${shortModel}`),
      branch && fg("success", ` ${shortBranch}`), compactContext, cost,
    ]);
  }
  const lines = [truncateToWidth(row, width, "…")];
  const messages = [...statuses.values()]
    .map((text) => text.replace(/[\r\n\t]/g, " "))
    .filter((text) => text.trim());
  if (messages.length) lines.push(truncateToWidth(join(messages), width, "…"));
  return lines;
}

export default function statusline(pi) {
  let dispose;
  let invalidateFooter = () => {};
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    dispose?.();
    ctx.ui.setFooter((tui, theme, footerData) => {
      let stopped = false, pending = false, dirty = true;
      let git, snapshot;
      const controller = new AbortController();
      const invalidate = () => { dirty = true; tui.requestRender(); };
      invalidateFooter = invalidate;
      const unsubscribe = footerData.onBranchChange(invalidate);
      const refresh = async () => {
        if (stopped || pending) return;
        pending = true;
        const next = await readGit(ctx.cwd, controller.signal);
        pending = false;
        if (stopped) return;
        git = next;
        invalidate();
      };
      // Refresh externally changed files and usage notices even while Pi is idle.
      const timer = setInterval(refresh, 2000);
      timer.unref();
      void refresh();
      dispose = () => {
        if (stopped) return;
        stopped = true;
        clearInterval(timer);
        controller.abort();
        unsubscribe();
      };
      return {
        dispose,
        invalidate() { dirty = true; },
        render(width) {
          // The model/thinking getters remain live, including shortcut changes.
          const model = ctx.model;
          const leaf = ctx.sessionManager.getLeafId();
          const session = ctx.sessionManager.getSessionId();
          if (dirty || snapshot?.leaf !== leaf || snapshot?.session !== session || snapshot?.model !== model) {
            snapshot = {
              leaf, session, model,
              usage: sessionUsage(ctx.sessionManager.getEntries(), ctx.modelRegistry),
              context: ctx.getContextUsage(),
            };
            dirty = false;
          }
          return renderStatusline(width, theme, {
            ...snapshot, git, cwd: ctx.cwd, thinking: pi.getThinkingLevel(),
            autoCompact: pi.getSettings().compaction?.enabled !== false,
          }, footerData.getExtensionStatuses());
        },
      };
    });
  });
  // Tool/native usage can be appended without moving to a new branch. Never
  // rescan the ledger on each streamed token or editor keystroke.
  for (const event of ["message_end", "tool_execution_end", "session_compact", "session_tree", "model_select"]) {
    pi.on(event, (_event, ctx) => {
      if (ctx.mode === "tui") invalidateFooter();
    });
  }
  pi.on("session_shutdown", () => {
    dispose?.();
    dispose = undefined;
    invalidateFooter = () => {};
  });
}
