---
description: Propose one reusable lesson from this session for the wiki; nothing is written without approval
argument-hint: "[topic to focus on]"
---
Review this session and propose at most one lesson worth keeping.

Focus for this run: ${@:-none}

## Steps

1. Look for one reusable lesson: a mistake that cost time, a non-obvious fact that changed a decision, or a check that caught a real problem. Skip anything already covered by `AGENTS.md`, a loaded skill, or repository docs.

2. If nothing in the session qualifies, say "No lesson worth keeping" and stop. That is a valid result.

3. Otherwise, draft the lesson in this shape:
   - **Cue:** the situation that should trigger the lesson, specific enough to recognize next time.
   - **Lesson:** what to do differently, in one or two sentences.
   - **Evidence:** what happened in this session that supports it, with file paths, commands, or error text.
   - **Confidence:** high, medium, or low, with one line on why.

4. Do not write anything. Ask whether to save the draft, edit it, or drop it.

5. Only if the user approves, save it with the `wiki-save` skill. If that skill is unavailable on this host, return the final text for the user to file.
