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

Complete each row in order before starting the next one. Honor its `Owner` assignment; `inline` means do not delegate that row. For `scout`, `worker`, or `reviewer`, launch the named subagent with that row's bounded task, relevant repository context, authority boundary, success criteria, verification, and expected report. Wait for and inspect its result before running the row's verification in the current session. Keep decisions and final acceptance with the parent; do not let subagents delegate further. Stop and report a launch or execution failure rather than silently switching to inline work.

| Mode | Action |
| --- | --- |
| **direct** | Perform the task and mark it done. |
| **inspect** | Read the relevant files, callers, and tests, or assign the scoped investigation to `scout`. Record and check the findings before continuing. |
| **decide** | Compare the concrete options, state the recommendation, and get user approval when the choice changes scope or behavior. |
| **edit** | Change only the listed files, or assign that change to `worker`, then run focused checks for those files. |
| **review** | Re-read the request and repository rules, inspect the full diff inline or assign a fixed-point review to `reviewer`, and report or fix findings before continuing. |

Stop if a verification check fails. Diagnose the failure before moving to the next row.

### 3. Wrap up

- Run the repository's required test suite.
- Run `/code-review` across the full diff.
- Summarize changed files, verification results, and remaining risks.
- Commit only when the user requested a commit.
