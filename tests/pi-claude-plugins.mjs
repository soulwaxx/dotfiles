import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import register, { parseFrontmatter, piToolName, sync } from "../config/pi/extensions/claude-plugins.ts";

const write = (path, content) => {
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, content);
};
const skill = (name, body = "Body.") => `---\nname: ${name}\ndescription: ${name} skill\n---\n${body}\n`;
const webTools = "ext:pi-web-access/web_enable, ext:pi-web-access/web_search";

// An agent dir with personal skills/agents and one linked plugin that overlaps them.
function fixture() {
	const base = realpathSync(mkdtempSync(join(tmpdir(), "claude-plugins-")));
	const agentDir = join(base, "agent");
	const plugin = join(base, "plugin");
	const links = join(base, "links");
	write(join(agentDir, "skills/review/SKILL.md"), skill("review"));
	write(join(agentDir, "agents/reviewer.md"), "---\nname: reviewer\ndescription: mine\n---\nMine.\n");
	write(join(agentDir, "claude-plugins/agents/stale.md"), "---\nname: stale\n---\n");
	write(join(agentDir, "mcp.json"), JSON.stringify({ mcpServers: { notion: {}, "incident-io": {} } }));
	write(join(agentDir, "claude-plugins/config.json"), JSON.stringify({
		pluginsDir: join(links, "plugins"),
		models: { opus: "anthropic/claude-opus-5-5" },
		tools: { Grep: "grep, ext:pi-fff/grep", WebFetch: webTools },
		deniedTools: { WebFetch: "fetch_content" },
	}));
	mkdirSync(join(links, "plugins"), { recursive: true });
	symlinkSync(plugin, join(links, "plugins/team"));
	symlinkSync(join(base, "missing"), join(links, "plugins/gone"));
	write(join(plugin, "skills/review/SKILL.md"), skill("review", "Team copy."));
	write(join(plugin, "skills/manual/SKILL.md"), skill("manual", "Run python3 ${CLAUDE_SKILL_DIR}/scripts/check.py for $ARGUMENTS."));
	write(join(plugin, "skills/manual/references/notes.md"), "Root: ${CLAUDE_PLUGIN_ROOT}; dir: $CLAUDE_SKILL_DIR.");
	write(join(plugin, "agents/reviewer.md"), "Team reviewer body.\n");
	write(join(plugin, "agents/reader.md"), "---\nname: reader\ndescription: Read.\ntools: Read, Grep, WebFetch, mcp__notion__notion-fetch\nmodel: sonnet[1m]\n---\nRead.\n");
	write(join(plugin, "agents/shell.md"), "---\nname: shell\ndescription: Shell.\ntools: Read, Bash\nmaxTurns: 5\n---\nRun.\n");
	write(join(plugin, "agents/escape.md"), "---\nname: ../escape\ndescription: Escape.\n---\nNo.\n");
	write(join(plugin, "agents/writer.md"), [
		"---",
		"name: manual-writer",
		"description: Write one manual page.",
		"disallowedTools: Edit, NotebookEdit, WebFetch, mcp__claude_ai_Notion__notion-create-pages, mcp__incident-io__alert_list, mcp__jira__create",
		"model: opus",
		"effort: high",
		"background: true",
		"permissionMode: acceptEdits",
		"skills:",
		"  - manual",
		"  - review",
		"",
		"---",
		"Use ${CLAUDE_PLUGIN_ROOT}/templates.",
	].join("\n"));
	return { agentDir, plugin, base };
}

const generated = (agentDir, name) => join(agentDir, "claude-plugins/agents", `${name}.md`);

function load(agentDir) {
	const handlers = {};
	process.env.PI_CODING_AGENT_DIR = agentDir;
	register({ on: (name, handler) => { handlers[name] = handler; } });
	return handlers;
}

test("parses scalar, quoted, inline-list, block-list, and folded fields", () => {
	const { fields, body } = parseFrontmatter("---\na: plain\nb: \"q: x\"\nc: [x, 'y']\nd:\n  - one\n  - two\ne: >\n  folded\n  text\n---\nBody");
	assert.deepEqual(Object.fromEntries(fields), { a: "plain", b: "q: x", c: ["x", "y"], d: ["one", "two"], e: "folded text" });
	assert.equal(body, "Body");
	assert.equal(parseFrontmatter("No frontmatter").fields.size, 0);
});

test("maps Claude Code MCP tool names to pi servers", () => {
	const servers = ["notion", "incident-io"];
	assert.deepEqual(piToolName("mcp__claude_ai_Notion__notion-create-pages", servers), { name: "mcp__notion__notion_create_pages" });
	assert.deepEqual(piToolName("mcp__incident-io__team_list", servers), { name: "mcp__incident_io__team_list" });
	assert.deepEqual(piToolName("mcp__incident-io", servers), { name: "mcp__incident_io" });
	assert.deepEqual(piToolName("mcp__jira__create", servers), { name: "mcp__jira__create", unknownServer: "jira" });
	assert.deepEqual(piToolName("Edit", servers), { name: "Edit" });
});

test("is a no-op without the Nix-written config", () => {
	const { agentDir } = fixture();
	writeFileSync(join(agentDir, "claude-plugins/config.json"), "{}");
	assert.match(sync(agentDir).warnings[0], /"pluginsDir" must be a path/);
	const empty = realpathSync(mkdtempSync(join(tmpdir(), "claude-plugins-")));
	assert.deepEqual(sync(empty).skillPaths, []);
	assert.ok(!existsSync(join(empty, "claude-plugins")));
});

test("personal skills and agents win; other plugin entries merge into the package", () => {
	const { agentDir, plugin, base } = fixture();
	const { skillPaths, warnings } = sync(agentDir);
	assert.deepEqual(skillPaths, [join(plugin, "skills/manual")]);
	assert.ok(!existsSync(generated(agentDir, "reviewer")));
	assert.ok(!existsSync(generated(agentDir, "stale")));
	assert.ok(existsSync(generated(agentDir, "reader")));
	assert.deepEqual(warnings, [
		`plugin gone not found at ${join(base, "links/plugins/gone")}`,
		`agent ${join(plugin, "agents/escape.md")}: unsupported name "../escape"`,
		"agent manual-writer: no pi MCP server matches jira in disallowedTools",
		"agent manual-writer: ignored unsupported field permissionMode",
	]);
});

test("translates Claude Code agent frontmatter for pi-subagents", () => {
	const { agentDir, plugin } = fixture();
	sync(agentDir);
	assert.equal(readFileSync(generated(agentDir, "manual-writer"), "utf8"), [
		"---",
		'name: "manual-writer"',
		'description: "Write one manual page."',
		'model: "anthropic/claude-opus-5-5"',
		'thinking: "high"',
		"run_in_background: true",
		'disallowed_tools: "Edit, NotebookEdit, fetch_content, mcp__notion__notion_create_pages, mcp__incident_io__alert_list, mcp__jira__create, ask_user_question"',
		"prompt_mode: replace",
		"skills: false",
		"---",
		`First read ${join(agentDir, "AGENTS.md")} and every AGENTS.md that applies to your working directory.`,
		"",
		`Before starting, read and follow ${join(plugin, "skills/manual/SKILL.md")}, ${join(agentDir, "skills/review/SKILL.md")}.`,
		"",
		`Use ${plugin}/templates.`,
		"",
	].join("\n"));
});

test("expands Claude Code tool names into pi-subagents selectors", () => {
	const { agentDir } = fixture();
	sync(agentDir);
	const { fields } = parseFrontmatter(readFileSync(generated(agentDir, "reader"), "utf8"));
	assert.equal(fields.get("tools"), `Read, grep, ext:pi-fff/grep, ${webTools}, mcp__notion__notion_fetch`);
	assert.equal(fields.get("model"), "sonnet");
	assert.equal(fields.get("disallowed_tools"), "ask_user_question");
	const shell = parseFrontmatter(readFileSync(generated(agentDir, "shell"), "utf8")).fields;
	// Without an ext: selector pi-subagents would admit every extension tool.
	assert.equal(shell.get("tools"), "Read, Bash, ext:claude-plugins");
	assert.equal(shell.get("max_turns"), "5");
	assert.match(readFileSync(generated(agentDir, "shell"), "utf8"), /^max_turns: 5$/m);
	assert.ok(!existsSync(join(agentDir, "escape.md")));
});

test("removes generated agents when the plugin links are gone", () => {
	const { agentDir, base } = fixture();
	sync(agentDir);
	writeFileSync(join(agentDir, "claude-plugins/config.json"), JSON.stringify({ pluginsDir: join(base, "none") }));
	sync(agentDir);
	assert.ok(!existsSync(generated(agentDir, "manual-writer")));
});

test("hides plugin skills from the model's skill list only", () => {
	const { agentDir, plugin } = fixture();
	const handlers = load(agentDir);
	const skills = [
		{ name: "manual", filePath: join(plugin, "skills/manual/SKILL.md"), disableModelInvocation: false },
		{ name: "review", filePath: join(agentDir, "skills/review/SKILL.md"), disableModelInvocation: false },
	];
	handlers.before_agent_start({ messageType: "user", prompt: "hi", systemPromptOptions: { skills } });
	assert.deepEqual(skills.map((s) => s.disableModelInvocation), [true, false]);
});

test("resolves Claude Code path variables in plugin file reads only", () => {
	const { agentDir, plugin } = fixture();
	const handlers = load(agentDir);
	assert.deepEqual(handlers.resources_discover(), { skillPaths: [join(plugin, "skills/manual")] });
	const read = (path, text) => handlers.tool_result(
		{ toolName: "read", input: { path }, content: [{ type: "text", text }, { type: "image", data: "x" }] },
		{ cwd: plugin },
	);
	assert.deepEqual(read("skills/manual/references/notes.md", "Root: ${CLAUDE_PLUGIN_ROOT}; dir: $CLAUDE_SKILL_DIR."), {
		content: [{ type: "text", text: `Root: ${plugin}; dir: ${join(plugin, "skills/manual")}.` }, { type: "image", data: "x" }],
	});
	assert.equal(read(join(agentDir, "skills/review/SKILL.md"), "${CLAUDE_SKILL_DIR}"), undefined);
	assert.equal(read("skills/manual/SKILL.md", "No variables."), undefined);
});

test("tells the model the variable values of an invoked plugin skill", () => {
	const { agentDir, plugin } = fixture();
	const handlers = load(agentDir);
	const location = join(plugin, "skills/manual/SKILL.md");
	const start = (args) => handlers.before_agent_start({
		messageType: "user",
		systemPromptOptions: { skills: [] },
		prompt: `<skill name="manual" location="${location}">\nReferences are relative to ${dirname(location)}.\n\nRun python3 \${CLAUDE_SKILL_DIR}/scripts/check.py for $ARGUMENTS.\n</skill>${args}`,
	});
	assert.deepEqual(start("\n\ncheck page.md"), {
		message: {
			customType: "claude-plugins",
			content: `Claude Code variables in the manual skill: \${CLAUDE_SKILL_DIR} is ${join(plugin, "skills/manual")}; $ARGUMENTS is "check page.md".`,
			display: false,
		},
	});
	assert.match(start("").message.content, /\$ARGUMENTS is empty/);
	assert.equal(handlers.before_agent_start({ messageType: "user", prompt: "plain prompt", systemPromptOptions: { skills: [] } }), undefined);
});
