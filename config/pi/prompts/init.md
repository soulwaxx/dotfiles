---
description: Survey this repo and generate (or refresh) its AGENTS.md
argument-hint: "[extra focus areas]"
---
Generate an `AGENTS.md` for this repository (the equivalent of Claude Code's `/init`).

Extra focus areas for this run: ${@:-none}

## Steps

1. Check existing root, ancestor, and relevant nested instruction files, including `AGENTS.md`, `CLAUDE.md`, and `.pi/AGENTS.md`. Verify which files the target agent actually loads and their scopes; do not assume links or other agents' formats are interchangeable. If instructions exist, treat this as a refresh: preserve hand-written constraints that remain intentional and accurate. If none exists, create `AGENTS.md` at the repository root.

2. Survey these areas in sequence and record concise notes before drafting:
   - Build and toolchain: package manager, language versions, lockfiles, and the canonical build, run, test, lint, and format commands. Read them from source files instead of guessing.
   - Architecture: top-level module layout, entry points, and how the main pieces fit together.
   - Conventions: directory ownership, naming patterns, and repository-specific rules.
   - Verification gates: how tests run and what must pass before work is complete.
   - Dependencies and environment: dependency sources, required environment variables, secrets conventions, and development-shell or bootstrap steps.

3. Synthesize the notes into a concise `AGENTS.md`. Keep rules that prevent wrong decisions or costly rediscovery, even when the underlying fact is discoverable. Avoid duplicating a README or rules already maintained in another loaded scope. Include:
   - One-paragraph project overview.
   - Short architecture and data-flow description.
   - Key directories and their ownership.
   - Exact verification commands cited from repository files.
   - Dependencies and environment setup.
   - Non-obvious conventions and failure modes.

4. Cite discovered commands instead of inventing them. Mark an unconfirmed gate as unverified.

5. Check paths, command definitions, prerequisites, and overlapping instruction scopes against the sources. Run a safe, relevant cited check when its prerequisites are available; do not install dependencies, start privileged services, deploy, or run destructive checks just to validate the file. Report what ran, what was only inspected, failures, and any unverified gate.
