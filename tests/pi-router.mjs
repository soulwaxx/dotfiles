import assert from "node:assert/strict";
import test from "node:test";
import register from "../config/pi/extensions/auto-router.ts";

let virtual;
register({ registerVirtualModel: (definition) => { virtual = definition; } });
const { provider, route } = virtual;
const physical = (tier) => ({ provider, id: `claude-${tier}-5-5`, api: "anthropic-messages", input: ["text", "image"] });
const haiku = physical("haiku");
const sonnet = physical("sonnet");
const opus = physical("opus");
const catalog = [haiku, sonnet, opus];
const user = (content) => ({ role: "user", content });
const pick = (request, available = catalog, hasConfiguredAuth = () => true) => route({
	reason: "user", thinkingLevel: "medium", messages: [], ...request,
}, {
	modelRegistry: { find: (p, id) => available.find((model) => model.provider === p && model.id === id), hasConfiguredAuth },
});
const expected = (model, thinkingLevel) => ({ model, thinkingLevel });

test("registers one selectable virtual model with three thinking levels", () => {
	assert.equal(`${provider}/${virtual.id}`, "anthropic/auto");
	assert.deepEqual(virtual.thinkingLevels, ["low", "medium", "high"]);
});

for (const [prompt, model, thinking] of [
	["Hello!", haiku, "low"],
	["What is a Git rebase?", haiku, "low"],
	["What does `git diff --stat` do?", haiku, "low"],
	["What is our plan?", sonnet, "medium"],
	["What is a Git rebase? Then rebase this branch.", sonnet, "medium"],
	["Add tests for this parser.", sonnet, "medium"],
	["Fix it.", sonnet, "medium"],
	["Find the root cause of this flaky test.", opus, "high"],
	["Review the migration and its tradeoffs.", opus, "high"],
]) {
	test(`routes ${JSON.stringify(prompt)}`, () => {
		const messages = [user("Review the architecture."), { role: "toolResult", content: "deadlock" }, user(prompt)];
		assert.deepEqual(pick({ messages }), expected(model, thinking));
	});
}

test("image inputs cannot take the quick path or fall back to a text-only model", () => {
	const messages = [user([{ type: "text", text: "What is this?" }, { type: "image", data: "xx", mimeType: "image/png" }])];
	assert.deepEqual(pick({ messages }), expected(sonnet, "medium"));
	assert.deepEqual(pick({ messages }, [{ ...sonnet, input: ["text"] }, opus]), expected(opus, "medium"));
});

test("low budgets reasoning without changing the task tier; high explicitly selects deep", () => {
	assert.deepEqual(pick({ thinkingLevel: "low", messages: [user("Fix it.")] }), expected(sonnet, "low"));
	assert.deepEqual(pick({ thinkingLevel: "low", messages: [user("Audit the migration.")] }), expected(opus, "medium"));
	assert.deepEqual(pick({ thinkingLevel: "high", messages: [user("Hi")] }), expected(opus, "high"));
});

test("sticks to the in-flight model and reasoning level; retries prefer the failed route", () => {
	const previous = expected(opus, "high");
	assert.deepEqual(pick({ reason: "continuation", previous }), previous);
	assert.deepEqual(pick({ reason: "retry", previous }), previous);
	assert.deepEqual(pick({ reason: "retry", previous, failed: expected(haiku, "low") }), expected(haiku, "low"));
	assert.deepEqual(pick({ previous, messages: [user("Go ahead.")] }), previous);
	assert.deepEqual(pick({ previous, messages: [user("Hi!")] }), expected(haiku, "low"));
	assert.deepEqual(pick({ previous, thinkingLevel: "low", messages: [user("Go ahead.")] }), expected(sonnet, "low"));
});

test("direct requests and continuations without a usable prior route default to standard", () => {
	const previous = expected({ ...opus, provider: "another-provider" }, "high");
	assert.deepEqual(pick({ reason: "continuation", previous }), expected(sonnet, "medium"));
	assert.deepEqual(pick({ reason: "direct", previous: expected(opus, "high"), messages: [user("Audit the migration.")] }), expected(sonnet, "medium"));
});

test("skips missing, virtual, and unconfigured targets; never changes providers", () => {
	const request = { messages: [user("Audit the migration.")] };
	assert.deepEqual(pick(request, [haiku, sonnet]), expected(sonnet, "high"));
	assert.deepEqual(pick(request, [{ ...opus, api: "pi-virtual" }, haiku, sonnet], (m) => m !== sonnet), expected(haiku, "high"));
	assert.throws(() => pick(request, catalog, () => false), /anthropic\/auto: none .* available/);
	assert.throws(() => pick(request, [{ ...sonnet, provider: "another-provider" }]), /anthropic\/auto: none .* available/);
});
