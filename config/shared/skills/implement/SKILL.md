---
name: implement
description: Execute an execution table produced by /grilling, completing and verifying each step in order.
disable-model-invocation: true
---

Execute the work described by the most recent execution table in the conversation. If none exists, ask the user to run `/grilling` first.

## Process

### 1. Locate the table

Find the last `## Execution table` in the conversation.

### 2. Execute row by row

Complete each row in the current session before starting the next one. Run its verification check immediately after the work.

| Mode | Action |
| --- | --- |
| **direct** | Perform the task and mark it done. |
| **inspect** | Read the relevant files, callers, and tests. Record the findings before continuing. |
| **decide** | Compare the concrete options, state the recommendation, and get user approval when the choice changes scope or behavior. |
| **edit** | Change only the listed files, then run focused checks for those files. |
| **review** | Re-read the request and repository rules, inspect the full diff, and report or fix findings before continuing. |

Stop if a verification check fails. Diagnose the failure before moving to the next row.

### 3. Wrap up

- Run the repository's required test suite.
- Run `/code-review` across the full diff.
- Summarize changed files, verification results, and remaining risks.
- Commit only when the user requested a commit.
