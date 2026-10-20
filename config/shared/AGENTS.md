# Agent Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

Use judgment: keep the process proportional to the task's risk and scope.

## 1. Think Before Coding

**Make consequential assumptions visible. Ask when the answer matters.**

Before implementing:
- For low-risk ambiguity, state a reasonable assumption and proceed.
- Ask when the answer changes scope, safety, correctness, or a hard-to-reverse decision.
- Inspect available evidence before asking the user for facts you can verify.
- If a simpler approach meets the goal, prefer it. Explain material tradeoffs.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

If the evidence does not support a change, making no change is a valid result; say so.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Verify the result with focused checks.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

Show a brief plan when it helps coordination or makes complex work easier to follow. Keep routine task planning internal.

Run the checks relevant to the change and follow repository verification gates. Retry a failed check when new evidence or a concrete fix justifies it. Stop and report the blocker when verification is unavailable or repeated attempts make no progress.

## 5. Communication

**The user often switches between sessions. Make every reply easy to pick up cold.**

Language:
- Use plain English: short sentences, common words, active voice.
- No idioms, slang, or wordplay. Define a technical term the first time if it is not standard.

Structure:
- Start with the bottom line: the answer or current status in 1-2 sentences.
- Then details, as short paragraphs, bullets, or headers. No walls of text.
- End with a next step when action or a decision is needed.
- For longer work, report meaningful progress and blockers rather than narrating routine steps.

Length:
- Short by default. Go longer only when the task needs it.
