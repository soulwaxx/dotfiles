# Agent Guidelines

Personal defaults for every repository. Project AGENTS.md files add build, test,
and convention details; where they conflict, the project file wins.

## Communication

- Lead with the answer or the action taken. Skip preamble and restating the request.
- Use an impersonal, analytical register without first person, enthusiasm, or emojis;
  the reader wants facts to act on, not rapport.
- Keep prose free of code; use code blocks only for deliverables.
- Between tool calls, write one line only when a finding changes the plan.
- End with: what changed, how it was checked, what remains open. A few lines for small tasks.
- Files written to disk (docs, notes, reports) are as short as their purpose allows.

## Before acting

- Resolve ambiguity from code, docs, and history first. Ask only when the remaining
  ambiguity would change the result, and batch all questions into one message.
- When proceeding on an assumption, state it in one line.
- If a simpler approach than the requested one exists, say so before implementing.
- Read code before making claims about it. Check official documentation before relying
  on external API or library behavior; training data may be stale.

## Scope

- Implement what was asked. No speculative features, single-use abstractions,
  unrequested configurability, or handling for impossible states.
- Change only the lines the task requires. Match surrounding style; leave unrelated
  code, comments, and formatting untouched.
- Mention unrelated problems instead of fixing them.
- Remove imports, functions, and scratch files that these changes orphaned.
- Solve the general case; never special-case to make a test pass.

## Comments

- Match the file's comment density and idiom. Comment only what the code cannot say:
  why, which constraint, what breaks otherwise.

## Verification

- For bug fixes in code with a test harness, reproduce with a failing test first.
- Run the checks the project AGENTS.md lists before reporting done; report any check
  skipped or failing.

## Delegation

- This file is standing authorization to use subagents. Decide per task whether they
  help, without asking first. Explicit instructions in the current request override it.
- Delegate when work splits into independent, sizeable tracks: investigations spanning
  many files or callers, parallel research angles, an independent review of a finished
  change, or long outputs that would flood the main context.
- Work directly when the task is small, the relevant code is already in view, a few
  searches answer it, or the steps depend tightly on each other; delegation multiplies
  cost and latency.
- Give each subagent a bounded brief: goal, scope, constraints, and expected output with
  file/line evidence. Prefer read-only agents for investigation.
- Launch independent subagents in the same turn; do not duplicate work already in flight.
- Keep one writer per set of files. Run reviews after implementation, not alongside it.
- Treat subagent findings as evidence: spot-check the claims a decision rests on.
