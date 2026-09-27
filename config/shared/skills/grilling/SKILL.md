---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
disable-model-invocation: true
---

Interview me relentlessly about every aspect of this until we reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one by one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a fact can be found by exploring the environment (filesystem, tools, and so on), look it up rather than asking me. The decisions are mine: put each one to me and wait for my answer.

Do not act on it until I confirm we have reached a shared understanding.

Once I confirm, ask one more question: should execution stay inline or dispatch eligible steps to subagents? Recommend a choice based on the actual steps. Wait for my answer, then evaluate every step and emit an execution table. Do not stop at "shared understanding."

**Classify each step.** Choose one mode:

| Mode | Use when |
| --- | --- |
| **direct** | Needs a user decision, a single read, or a trivial edit |
| **inspect** | Requires broad read-only codebase investigation |
| **decide** | Requires design analysis or an architecture decision |
| **edit** | Makes well-specified file changes |
| **review** | Checks the completed diff against the request and repository rules |

Steps are ordered. Each step depends on the one before it unless stated otherwise.

**Assign an owner to every step.** For inline execution, use `inline` throughout. For dispatched execution, use `scout` for broad `inspect` steps, `worker` for bounded `edit` steps, and `reviewer` for `review` steps with an explicit fixed point; keep decisions, trivial reads/edits, and steps without a suitable agent `inline`. Do not assign concurrent writers to the same worktree. State each subagent's specific deliverable and verification in its row; do not delegate a vague whole-plan task.

**Emit:**

## Goal

One-line success condition.

## Execution table

| # | Step | Mode | Owner | Verify | Notes |
|---|------|------|-------|--------|-------|

## Out of scope

What this deliberately does not do.

A step without a checkable verification is too vague. Sharpen it until done is distinguishable from not done.

**Execution.** After emitting the table, ask the user whether to execute it now. `/implement` performs every row in order, launching the assigned subagents from the current session and checking their results before continuing.
