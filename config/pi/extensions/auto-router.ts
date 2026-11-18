import type { ExtensionAPI, ExtensionContext, ModelRoute, ModelRouteRequest } from "@earendil-works/pi-coding-agent";

const provider = "anthropic";
const models = {
	quick: "claude-haiku-5-5",
	standard: "claude-sonnet-5-5",
	deep: "claude-opus-5-5",
} as const;
type Tier = keyof typeof models;
const fallback: Record<Tier, readonly Tier[]> = {
	quick: ["quick", "standard", "deep"],
	standard: ["standard", "deep", "quick"],
	deep: ["deep", "standard", "quick"],
};

const followUp = /^(?:yes|no|sure|please do|go ahead|do it|continue|keep going|try again|sounds good)(?:,? please)?[.!?]*$/i;
const greeting = /^(?:hi|hello|hey|thanks|thank you|good morning|good evening)[.!?]*$/i;
const definition = /^what (?:is|are) (?:an? )?(?!(?:this|that|it|the|our|your|my|their|its)\b)[\w.+#/-]+(?: [\w.+#/-]+){0,2}\?$/i;
const commandQuestion = /^what does `[^`\n]+` do\?$/i;
const deepWork = /\b(?:root cause|race condition|deadlock|intermittent|flaky|regression|architecture|cross[- ](?:module|service|cutting)|breaking change|(?:design|security|threat|risk) review|threat model|audit|migration|trade[- ]?offs?|deep dive)\b/i;

function userTurn(messages: ModelRouteRequest["messages"]) {
	const content = messages.findLast((message) => message.role === "user")?.content ?? "";
	if (typeof content === "string") return { text: content.trim(), hasImage: false };
	return {
		text: content.flatMap((block) => (block.type === "text" ? [block.text] : [])).join("\n").trim(),
		hasImage: content.some((block) => block.type === "image"),
	};
}

function route(request: ModelRouteRequest, { modelRegistry }: ExtensionContext): ModelRoute {
	const { reason, previous, failed, thinkingLevel } = request;
	const { text, hasImage } = reason === "user" ? userTurn(request.messages) : { text: "", hasImage: false };
	const followPrevious = reason === "continuation" ||
		(reason === "user" && thinkingLevel === "medium" && !hasImage && followUp.test(text));
	const sticky = reason === "retry" ? failed ?? previous : followPrevious ? previous : undefined;
	const available = (id: string) => {
		const model = modelRegistry.find(provider, id);
		if (model && model.api !== "pi-virtual" && (!hasImage || model.input.includes("image")) && modelRegistry.hasConfiguredAuth(model)) {
			return model;
		}
	};

	// Keep tool loops and retries on the same model and effort. A manually selected
	// model outside this router's pool is not an implicit routing target.
	if (sticky && sticky.model.provider === provider && Object.values(models).some((id) => id === sticky.model.id)) {
		const model = available(sticky.model.id);
		if (model) return { model, thinkingLevel: sticky.thinkingLevel ?? thinkingLevel };
	}

	let tier: Tier = "standard";
	if (reason === "user") {
		if (thinkingLevel === "high" || deepWork.test(text)) tier = "deep";
		else if (!hasImage && text.length <= 160 && (greeting.test(text) || definition.test(text) || commandQuestion.test(text))) {
			tier = "quick";
		}
	}

	const efforts = {
		quick: "low",
		standard: thinkingLevel === "low" ? "low" : "medium",
		deep: thinkingLevel === "low" ? "medium" : "high",
	} as const;
	// Keep fallback in the same provider and preserve the chosen effort.
	for (const candidate of fallback[tier]) {
		const model = available(models[candidate]);
		if (model) return { model, thinkingLevel: efforts[tier] };
	}
	throw new Error("anthropic/auto: none of its Claude 5.5 models are available. Check /login and pi --list-models, or select a physical model.");
}

export default function (pi: ExtensionAPI) {
	pi.registerVirtualModel({
		provider,
		id: "auto",
		name: "Auto (Claude)",
		thinkingLevels: ["low", "medium", "high"],
		// Shared catalog limits, shown until the first physical response.
		contextWindow: 1_000_000,
		maxTokens: 128_000,
		route,
	});
}
