import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, isAbsolute, join, relative, resolve, sep } from "node:path";

// Claude Code plugin compatibility for pi and @tintinweb/pi-subagents.
// modules/claude-plugins links the configured plugin roots into
// config.pluginsDir; modules/pi.nix writes <agent dir>/claude-plugins/config.json
// and declares that directory as a local pi package. Names that the user's
// skills or agents directories already define win; the rest merge in:
// - skills load through resources_discover and are hidden from the model's
//   skill list, like disable-model-invocation, so only /skill:<name> loads them;
// - agents are translated into the package's agents/ directory, which
//   pi-subagents ranks below every personal and project agent;
// - ${CLAUDE_SKILL_DIR}, ${CLAUDE_PLUGIN_ROOT}, and $ARGUMENTS, which pi leaves
//   literal, are resolved in plugin file reads and /skill: invocations.
// Plugin commands/, hooks, MCP servers, and .lsp.json are not loaded; add them
// when a configured plugin ships one.

const CLAUDE_VARS = /\$\{CLAUDE_(SKILL_DIR|PLUGIN_ROOT)\}|\$CLAUDE_(SKILL_DIR|PLUGIN_ROOT)\b/g;
const ARGUMENTS = /\$\{ARGUMENTS\}|\$ARGUMENTS\b/;
// Matches the block pi builds when it expands /skill:name args.
const SKILL_BLOCK = /^<skill name="([^"]+)" location="([^"]+)">\n([\s\S]*?)\n<\/skill>(?:\n\n([\s\S]+))?$/;
// Claude Code agent fields that pi-subagents spells differently, or the same.
const RENAMED: Record<string, string> = {
	description: "description",
	color: "color",
	effort: "thinking",
	memory: "memory",
	isolation: "isolation",
};

type Value = string | string[];
type Skill = { names: string[]; dir: string };
type Vars = { root: string; skillDir?: string };
export type Config = {
	/** Directory of links to Claude Code plugin roots. */
	pluginsDir: string;
	/** Claude Code model alias -> pi model. */
	models?: Record<string, string>;
	/** Claude Code tool name -> comma-separated pi-subagents `tools:` entries. */
	tools?: Record<string, string>;
	/** Claude Code tool name -> comma-separated pi tool names to deny. */
	deniedTools?: Record<string, string>;
};

const unquote = (value: string) => {
	if (value.length > 1 && value[0] === '"' && value.at(-1) === '"') return JSON.parse(value) as string;
	if (value.length > 1 && value[0] === "'" && value.at(-1) === "'") return value.slice(1, -1).replaceAll("''", "'");
	return value;
};

/** Top-level scalar, inline-list, block-list, and block-scalar frontmatter fields. */
export function parseFrontmatter(text: string): { fields: Map<string, Value>; body: string } {
	const fields = new Map<string, Value>();
	const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
	if (!match) return { fields, body: text };
	const lines = match[1].split(/\r?\n/);
	for (let i = 0; i < lines.length; i++) {
		const field = lines[i].match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
		if (!field) continue;
		const [, key, raw] = field;
		const value = raw.trim();
		if (value === "" || /^[|>][+-]?$/.test(value)) {
			const block: string[] = [];
			while (i + 1 < lines.length && /^(\s+\S|\s*$)/.test(lines[i + 1])) block.push(lines[++i]);
			const nonEmpty = block.filter((line) => line.trim());
			const items = nonEmpty.map((line) => line.match(/^\s*-\s+(.*)$/)?.[1]);
			if (value === "" && items.length && items.every((item) => item !== undefined)) {
				fields.set(key, items.map((item) => unquote(item!.trim())));
			} else {
				fields.set(key, nonEmpty.map((line) => line.trim()).join(value.startsWith("|") ? "\n" : " "));
			}
		} else if (value.startsWith("[") && value.endsWith("]")) {
			fields.set(key, value.slice(1, -1).split(",").map((item) => unquote(item.trim())).filter(Boolean));
		} else {
			fields.set(key, unquote(value));
		}
	}
	return { fields, body: text.slice(match[0].length) };
}

const list = (value: Value | undefined) =>
	value === undefined ? [] : Array.isArray(value) ? value : value.split(value.includes(",") ? "," : /\s+/).map((item) => item.trim()).filter(Boolean);
const scalar = (value: Value | undefined) => (Array.isArray(value) ? value.join(", ") : value);
const normalize = (name: string) => name.replace(/[^A-Za-z0-9_*]/g, "_");
const lookup = (map: Record<string, string> | undefined, key: string) =>
	Object.entries(map ?? {}).find(([name]) => name.toLowerCase() === key.toLowerCase())?.[1];

/**
 * Map a Claude Code MCP tool name to pi's `mcp__<server>__<tool>` spelling.
 * Claude.ai connectors (`claude_ai_<Name>`) map to a pi server named <Name>.
 */
export function piToolName(name: string, servers: string[]): { name: string; unknownServer?: string } {
	const match = name.match(/^mcp__(.+?)(?:__(.+))?$/);
	if (!match) return { name };
	const [, server, tool] = match;
	const known = [server, server.replace(/^claude_ai_/, "")]
		.map((candidate) => servers.find((s) => normalize(s).toLowerCase() === normalize(candidate).toLowerCase()))
		.find(Boolean);
	const mapped = `mcp__${normalize(known ?? server)}${tool ? `__${normalize(tool)}` : ""}`;
	return known ? { name: mapped } : { name: mapped, unknownServer: server };
}

export type AgentEnv = {
	agentDir: string;
	pluginRoot: string;
	servers: string[];
	config: Config;
	/** SKILL.md path for a skill name, as the merged skill set resolves it. */
	skillFile: (name: string) => string | undefined;
};

/** Translate one Claude Code agent file into a pi-subagents definition. */
export function translateAgent(source: string, file: string, env: AgentEnv) {
	const { fields, body } = parseFrontmatter(source);
	const warnings: string[] = [];
	const name = scalar(fields.get("name")) ?? basename(file, ".md");
	// The name becomes the generated file name.
	if (!/^[A-Za-z0-9_][\w.-]*$/.test(name)) return { name, content: undefined, warnings: [`agent ${file}: unsupported name ${JSON.stringify(name)}`] };
	const out = [`name: ${JSON.stringify(name)}`];
	if (!fields.has("description")) warnings.push(`agent ${name} has no description`);
	// pi-subagents maps Claude Code built-in names itself; the config covers
	// tools that pi provides through extensions.
	const tools = (key: string, map: Record<string, string> | undefined) => {
		const names = list(fields.get(key)).flatMap((tool) => {
			const expanded = lookup(map, tool);
			if (expanded) return expanded.split(",").map((entry) => entry.trim());
			const mapped = piToolName(tool, env.servers);
			if (mapped.unknownServer) warnings.push(`agent ${name}: no pi MCP server matches ${mapped.unknownServer} in ${key}`);
			return [mapped.name];
		});
		return [...new Set(names)];
	};
	const denied: string[] = [];
	const skillFiles: string[] = [];
	for (const [key, value] of fields) {
		if (key === "name") continue;
		else if (key in RENAMED) out.push(`${RENAMED[key]}: ${JSON.stringify(scalar(value))}`);
		else if (key === "model") {
			const model = scalar(value)!.replace(/\[1m\]$/i, "");
			if (model !== "inherit") out.push(`model: ${JSON.stringify(lookup(env.config.models, model) ?? model)}`);
		} else if (key === "tools") {
			// pi-subagents filters extension tools only when an ext: selector is
			// present; naming this extension, which registers no tools, turns the
			// filter on so the list stays as narrow as in Claude Code.
			const entries = tools(key, env.config.tools);
			if (!entries.some((entry) => entry.startsWith("ext:"))) entries.push("ext:claude-plugins");
			out.push(`tools: ${JSON.stringify(entries.join(", "))}`);
		} else if (key === "maxTurns") out.push(`max_turns: ${Number(scalar(value))}`);
		else if (key === "disallowedTools" || key === "disallowed_tools") denied.push(...tools(key, env.config.deniedTools));
		else if (key === "background") out.push(`run_in_background: ${scalar(value) === "true"}`);
		else if (key === "skills") {
			for (const skill of list(value)) {
				const path = env.skillFile(skill);
				if (path) skillFiles.push(path);
				else warnings.push(`agent ${name}: skill ${skill} not found`);
			}
		} else warnings.push(`agent ${name}: ignored unsupported field ${key}`);
	}
	// ask_user_question needs the parent's UI, which a child lacks.
	denied.push("ask_user_question");
	out.push(`disallowed_tools: ${JSON.stringify([...new Set(denied)].join(", "))}`);
	// Claude Code preloads `skills:` and does not inherit the parent's skills.
	// pi-subagents preloads only from standard skill directories, so the body
	// reads them by path instead, as the dotfiles agents do.
	out.push("prompt_mode: replace", "skills: false");
	const preamble = [
		`First read ${join(env.agentDir, "AGENTS.md")} and every AGENTS.md that applies to your working directory.`,
		...(skillFiles.length ? [`Before starting, read and follow ${skillFiles.join(", ")}.`] : []),
	];
	const prompt = body.trim().replace(CLAUDE_VARS, (match, a, b) => ((a ?? b) === "PLUGIN_ROOT" ? env.pluginRoot : match));
	return { name, content: `---\n${out.join("\n")}\n---\n${preamble.join("\n\n")}\n\n${prompt}\n`, warnings };
}

/** Resolve Claude Code path variables for a file inside a plugin root. */
export function substituteVars(text: string, vars: Vars) {
	return text.replace(CLAUDE_VARS, (match, a, b) => {
		if ((a ?? b) === "PLUGIN_ROOT") return vars.root;
		return vars.skillDir ?? match;
	});
}

const realpath = (path: string) => {
	try {
		return realpathSync(path);
	} catch {
		return path;
	}
};
const expandHome = (path: string) => (path === "~" || path.startsWith("~/") ? join(homedir(), path.slice(1)) : path);
const isDir = (path: string) => existsSync(path) && statSync(path).isDirectory();
const readJson = (path: string) => JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;

/** `<dir>/<skill>/SKILL.md` entries, named by frontmatter and directory. */
function skillDirs(dir: string): Skill[] {
	if (!isDir(dir)) return [];
	return readdirSync(dir).sort().flatMap((entry) => {
		const file = join(dir, entry, "SKILL.md");
		if (!existsSync(file)) return [];
		const name = scalar(parseFrontmatter(readFileSync(file, "utf8")).fields.get("name")) ?? entry;
		return [{ names: [...new Set([name, entry])], dir: join(dir, entry) }];
	});
}

/** Package directory holding config.json and the generated agents/. */
export const packageDir = (agentDir: string) => join(agentDir, "claude-plugins");

export function sync(agentDir: string) {
	const warnings: string[] = [];
	const plugins: string[] = [];
	const skillPaths: string[] = [];
	const varsFor = (path: string): Vars | undefined => {
		const target = realpath(path);
		for (const root of plugins) {
			const rel = relative(root, target);
			if (rel === "" || rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) continue;
			const [top, skill] = rel.split(sep);
			return { root, skillDir: top === "skills" && skill ? join(root, "skills", skill) : undefined };
		}
	};
	const configFile = join(packageDir(agentDir), "config.json");
	if (!existsSync(configFile)) return { skillPaths, warnings, varsFor };
	let config: Config;
	try {
		config = readJson(configFile) as Config;
		if (typeof config.pluginsDir !== "string") throw new Error('"pluginsDir" must be a path');
	} catch (error) {
		warnings.push(`${configFile}: ${(error as Error).message}`);
		return { skillPaths, warnings, varsFor };
	}

	const agentsDir = join(agentDir, "agents");
	const userSkills = new Map<string, string>();
	for (const { names, dir } of skillDirs(join(agentDir, "skills"))) for (const name of names) userSkills.set(name, dir);
	const userAgents = new Set<string>();
	for (const file of isDir(agentsDir) ? readdirSync(agentsDir) : []) {
		if (!file.endsWith(".md")) continue;
		const fields = parseFrontmatter(readFileSync(join(agentsDir, file), "utf8")).fields;
		userAgents.add(scalar(fields.get("name")) ?? basename(file, ".md"));
	}
	const mcpFile = join(agentDir, "mcp.json");
	const servers = existsSync(mcpFile) ? Object.keys((readJson(mcpFile).mcpServers as object | undefined) ?? {}) : [];

	const pluginsDir = expandHome(config.pluginsDir);
	const merged = new Map<string, string>();
	for (const entry of isDir(pluginsDir) ? readdirSync(pluginsDir).sort() : []) {
		const root = realpath(join(pluginsDir, entry));
		if (!isDir(root)) {
			warnings.push(`plugin ${entry} not found at ${root}`);
			continue;
		}
		plugins.push(root);
		for (const { names, dir } of skillDirs(join(root, "skills"))) {
			if (names.some((name) => userSkills.has(name) || merged.has(name))) continue;
			for (const name of names) merged.set(name, dir);
			skillPaths.push(dir);
		}
	}

	const generated = new Map<string, string>();
	for (const root of plugins) {
		const dir = join(root, "agents");
		for (const file of isDir(dir) ? readdirSync(dir).sort() : []) {
			const path = join(dir, file);
			if (!file.endsWith(".md") || !statSync(path).isFile()) continue;
			const agent = translateAgent(readFileSync(path, "utf8"), path, {
				agentDir,
				pluginRoot: root,
				servers,
				config,
				skillFile: (name) => {
					const skill = userSkills.get(name) ?? merged.get(name);
					return skill && join(skill, "SKILL.md");
				},
			});
			// pi-subagents would rank a personal agent first anyway; skipping
			// also drops warnings about an agent that never loads.
			if (userAgents.has(agent.name) || generated.has(agent.name)) continue;
			warnings.push(...agent.warnings);
			if (agent.content) generated.set(agent.name, agent.content);
		}
	}

	// The package's agents/ directory holds only generated files.
	const outDir = join(packageDir(agentDir), "agents");
	mkdirSync(outDir, { recursive: true });
	for (const [name, content] of generated) {
		const file = join(outDir, `${name}.md`);
		if (!existsSync(file) || readFileSync(file, "utf8") !== content) writeFileSync(file, content);
	}
	for (const file of readdirSync(outDir)) {
		if (!generated.has(basename(file, ".md")) || !file.endsWith(".md")) rmSync(join(outDir, file), { recursive: true });
	}
	return { skillPaths, warnings, varsFor };
}

export default function (pi: ExtensionAPI) {
	const agentDir = expandHome(process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent"));
	// Runs at load, before pi-subagents reads package agents on session_start.
	const { skillPaths, warnings, varsFor } = sync(agentDir);

	pi.on("session_start", (_event, ctx) => {
		if (warnings.length && ctx.hasUI) ctx.ui.notify(`claude-plugins: ${warnings.join("; ")}`, "warning");
	});

	pi.on("resources_discover", () => ({ skillPaths }));

	pi.on("tool_result", (event, ctx) => {
		const path = (event.input as { path?: unknown }).path;
		if (event.toolName !== "read" || typeof path !== "string") return;
		const vars = varsFor(resolve(ctx.cwd, expandHome(path)));
		if (!vars) return;
		let changed = false;
		const content = event.content.map((part) => {
			if (part.type !== "text") return part;
			const text = substituteVars(part.text, vars);
			changed ||= text !== part.text;
			return { ...part, text };
		});
		return changed ? { content } : undefined;
	});

	pi.on("before_agent_start", (event) => {
		// Per-run copies: hiding here keeps every request's skill list consistent.
		for (const skill of event.systemPromptOptions.skills ?? []) {
			if (varsFor(skill.filePath)) skill.disableModelInvocation = true;
		}
		const block = event.messageType === "user" ? event.prompt?.match(SKILL_BLOCK) : undefined;
		if (!block) return;
		const [, name, location, body, args] = block;
		const vars = varsFor(location);
		if (!vars) return;
		const notes: string[] = [];
		if (vars.skillDir && /CLAUDE_SKILL_DIR/.test(body)) notes.push(`\${CLAUDE_SKILL_DIR} is ${vars.skillDir}`);
		if (/CLAUDE_PLUGIN_ROOT/.test(body)) notes.push(`\${CLAUDE_PLUGIN_ROOT} is ${vars.root}`);
		if (ARGUMENTS.test(body)) notes.push(`$ARGUMENTS is ${args ? JSON.stringify(args.trim()) : "empty"}`);
		if (!notes.length) return;
		return {
			message: {
				customType: "claude-plugins",
				content: `Claude Code variables in the ${name} skill: ${notes.join("; ")}.`,
				display: false,
			},
		};
	});
}
