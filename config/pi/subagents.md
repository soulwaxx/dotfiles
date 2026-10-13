## Subagent delegation

Use `@gotgenes/pi-subagents` only when the user or applicable project instructions authorize delegation. Task complexity alone is not authorization. Keep decisions, final acceptance, and trivial work in the parent session.

Use `scout` for read-only code investigation, `reviewer` for review against an explicit fixed point, `worker` for bounded implementation, and `obsidian-second-brain.wiki-vault` for authorized wiki work on macOS. Give each child a self-contained task, relevant paths, constraints, success criteria, and the required report. Children start without parent conversation history. Do not delegate further from a child.

Call `subagent` with `subagent_type`, `prompt`, and a short `description`. Agents run in the background by default and notify the parent on completion. Continue independent work instead of polling; use `get_subagent_result` with `wait: true` when the result is needed, and `steer_subagent` to redirect a running child. A blocked child asks through `ask_parent`; answer by resuming that same agent with the requested information.

Agents share the checkout: allow only one writer at a time, including the parent. Inspect each result and run the required verification before accepting it. Report launch or execution failures rather than silently switching runners or doing an assigned subagent task inline.
