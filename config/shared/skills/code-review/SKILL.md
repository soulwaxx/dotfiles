---
name: code-review
disable-model-invocation: true
description: "Review changes since a fixed point along two separate axes: repository standards and the originating issue or specification. Use for branch, pull request, or work-in-progress reviews."
---

Review changes since a fixed point supplied by the user. Include working-tree changes when the task requests a work-in-progress review; otherwise review committed changes through `HEAD`. Perform the two axes sequentially and report them separately:

- **Standards:** Does the code conform to this repository's documented standards?
- **Spec:** Does the code implement the originating issue, product requirements document, or specification?

If the repository documents an issue-tracker workflow, use it. Otherwise, fetch issue context with available tracker tools.

## Process

### 1. Pin the fixed point

Use the commit SHA, branch, tag, `main`, or relative ref supplied by the user. Ask for it if none was supplied.

Confirm that `git rev-parse <fixed-point>` resolves. Capture the commit list with `git log <fixed-point>..HEAD --oneline` and compute the merge base with `git merge-base <fixed-point> HEAD`.

For a committed-only review, capture `git diff <fixed-point>...HEAD`. For a work-in-progress review, capture `git diff <merge-base>` to include committed, staged, and unstaged changes to tracked files; also list untracked files with `git ls-files --others --exclude-standard` and inspect their contents. Do not modify the index or working tree. Continue if either the diff or the in-scope untracked files are non-empty; otherwise report that there are no changes to review.

### 2. Identify the spec source

Look for the originating specification in this order:

1. Issue references in commit messages, such as `#123`, `Closes #45`, or GitLab `!67`.
2. A path supplied by the user.
3. A matching file under `docs/`, `specs/`, or `.scratch/`.
4. The user's answer when no source is discoverable.

If no specification exists, skip the Spec axis and report `no spec available`.

### 3. Identify the standards sources

Read repository files that define coding rules, such as `AGENTS.md`, `CONTRIBUTING.md`, or `CODING_STANDARDS.md`.

Apply the smell baseline below in addition to repository rules. Repository rules override the baseline. Treat every smell as a judgement call, not a hard violation. Skip checks already enforced by tooling.

- **Mysterious Name:** A name does not reveal what the value or function represents. Rename it. If no honest name fits, revisit the design.
- **Duplicated Code:** The same logic appears in more than one changed location. Extract the shared shape.
- **Feature Envy:** A method reaches into another object's data more than its own. Move the method toward that data.
- **Data Clumps:** The same fields or parameters travel together. Bundle them into one type.
- **Primitive Obsession:** A primitive stands in for a domain concept. Give the concept a small type.
- **Repeated Switches:** The same type-based branch recurs. Replace it with polymorphism or one shared map.
- **Shotgun Surgery:** One logical change requires scattered edits. Gather the changing behavior into one module.
- **Divergent Change:** One file changes for unrelated reasons. Split those responsibilities.
- **Speculative Generality:** The diff adds abstractions or hooks that the specification does not require. Remove them.
- **Message Chains:** A caller depends on a long navigation chain. Hide the walk behind one method.
- **Middle Man:** A function or class only forwards calls. Remove it and call the real target.
- **Refused Bequest:** An implementation ignores most inherited behavior. Prefer composition.

### 4. Review standards

Inspect the complete diff against the repository rules and smell baseline. For each finding:

- cite the file and hunk;
- cite the repository rule when one applies;
- distinguish hard rule violations from judgement calls;
- name and quote the relevant smell when one applies.

Keep the Standards notes separate from specification concerns.

### 5. Review the specification

Re-read the diff using only the specification as the acceptance contract. Report:

- missing or partial requirements;
- behavior that was not requested;
- requirements that appear implemented incorrectly.

Quote the specification for every finding. Do not carry Standards findings into this section.

### 6. Report

Present findings under `## Standards` and `## Spec`. Do not merge or rerank the two sections.

End with one line that gives the finding count and worst issue within each axis. Do not select one winner across both axes.

## Why two axes

A change can follow every repository rule while implementing the wrong behavior. It can also satisfy the specification while breaking repository conventions. Separate reports prevent one result from hiding the other.
