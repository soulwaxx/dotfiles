# Agent instruction best practices for current coding models

## Question

Should the always-loaded Karpathy-inspired behavioral directives be retained when using state-of-the-art coding models, and what should replace them if they are removed?

## Finding

Use a small project-specific `AGENTS.md` plus a concise global heuristic file, not a large global behavior manual. Keep only context that models cannot reliably infer, load specialized workflows on demand, and enforce non-negotiable behavior with tests, permissions, or hooks rather than prose.

The existing `config/shared/AGENTS.md` should retain its four Karpathy-inspired principles in a substantially trimmed form. Generic response-style rules, procedural ceremony, and duplicated verification instructions do not justify their persistent context cost.

## Evidence

### The current rules are Karpathy-inspired, not a file authored by Karpathy

The four-part structure in `config/shared/AGENTS.md` closely matches the third-party `multica-ai/andrej-karpathy-skills` project: “Think Before Coding,” “Simplicity First,” “Surgical Changes,” and “Goal-Driven Execution.” That project describes its file as *derived from* Andrej Karpathy's observations and links to his post; it does not claim that Karpathy authored the resulting directives.[1]

Karpathy's original post identifies recurring coding-agent failure modes and argues that agents work well when given concrete success criteria.[2] The prescriptive four-section file is a later synthesis by another author.[1] The original X page could not be fetched directly in this environment because X returned HTTP 403; its URL and indexed excerpts were cross-checked against the source repository. Claims about the exact wording beyond those excerpts remain subject to that access limitation.

### Vendor guidance favors minimal, failure-driven persistent context

Anthropic recommends keeping `CLAUDE.md` short, including only broadly applicable information, and asking whether removing each line would cause mistakes. It explicitly warns that oversized instruction files can make important rules less effective.[3]

Anthropic's current memory documentation says persistent instructions should contain facts that must be available every session. It recommends adding an instruction after repeated mistakes or repeated corrections, keeping instructions specific and concise, and moving conditional material to path-scoped rules or skills.[4]

Anthropic's context-engineering guidance recommends starting with the minimal prompt that works with the best available model, then adding instructions or examples in response to observed failure modes. It also predicts progressively less human curation as model capabilities improve, while retaining just-in-time retrieval for specialized context.[5]

OpenAI's Codex documentation similarly presents `AGENTS.md` as layered project context. Its examples focus on repository commands, conventions, specialized directory overrides, and concise review rules; it recommends leaving formatting and lint enforcement to CI.[6]

The cross-vendor `AGENTS.md` specification describes the file as a repository-specific README for agents, with build commands, tests, conventions, and security considerations. It supports narrower nested files rather than one universal behavior document.[7]

### Tests and hard controls serve a different purpose from prose instructions

Anthropic distinguishes context from enforcement: persistent instructions guide behavior, while deterministic hooks should be used for actions that must occur or must be blocked. Its Claude Code best-practices guide also recommends explicit verification through tests, scripts, or screenshots instead of trusting plausible output.[3][4]

This supports retaining this repository's tests and flake checks. They provide objective feedback and do not constrain the model's reasoning strategy. Permission controls should likewise remain for credential access, catastrophic machine operations, and user consent for external side effects; these are authority boundaries, not coding-style guidance.

## Recommended split

1. **Always-loaded project context:** retain only repository-specific commands, ownership rules, non-obvious architecture, secret locations, and known activation hazards.
2. **Global behavioral prose:** retain only a short set of durable heuristics. Add further rules only after a recurring, measured failure.
3. **Specialized workflows:** retain as explicit skills or path-scoped instructions, using progressive disclosure.
4. **Verification:** keep tests, formatting, evaluation, and focused build checks as executable success criteria.
5. **Authority and safety:** keep deterministic denials for secrets and catastrophic operations and confirmation for external or destructive effects.
6. **Evaluation:** compare representative tasks before and after changing global instructions. Measure unnecessary diff size, clarification quality, regressions, check pass rate, and completion latency rather than relying on subjective impressions.

## Implication for this repository

The current Karpathy-inspired guidance is reasonable as a catalogue of historical agent failure modes, but its detailed stylistic and procedural rules are too generic to justify unconditional loading solely because those failures existed in earlier models. The selected approach is to keep a compact global version covering deliberate decisions, simplicity, surgical scope, and observable verification. Root `AGENTS.md` remains because it contains repository facts and hazards that even a strong model cannot infer cheaply or safely.

## Sources

1. [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) — source and provenance of the four-part directive file.
2. [Andrej Karpathy, “A few random notes from claude coding…”](https://x.com/karpathy/status/2015883857489522876) — original observations; direct fetch was blocked, so only indexed excerpts and the linked source repository were verifiable here.
3. [Anthropic, “Best practices for Claude Code”](https://www.anthropic.com/engineering/claude-code-best-practices) — concise persistent context, skills for conditional workflows, hooks for deterministic behavior, and verification.
4. [Anthropic, “How Claude remembers your project”](https://docs.anthropic.com/en/docs/claude-code/memory) — when to add persistent instructions, specificity, size, layering, and path-scoped rules.
5. [Anthropic, “Effective context engineering for AI agents”](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — minimal prompts, failure-driven iteration, and just-in-time context.
6. [OpenAI, “Custom instructions with AGENTS.md”](https://learn.chatgpt.com/docs/agent-configuration/agents-md) — instruction layering, concise rules, repository expectations, and CI boundaries.
7. [AGENTS.md open specification](https://agents.md/) — cross-vendor purpose, recommended content, and nested project instructions.
