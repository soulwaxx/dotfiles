# Vendoring provenance

This skill is **vendored and re-authored** from an upstream project. It is not a
verbatim copy — the upstream `claude/SKILL.md` is one monolithic file; here it is
condensed and split into progressive-disclosure `references/`. Keep that shape when
porting upstream changes: essentials in `SKILL.md`, depth in `references/`.

- **Upstream:** https://github.com/vidanov/aws-architecture-diagram-skill (MIT)
- **Canonical upstream files:** `claude/SKILL.md` + `references/*.md`
- **Last reconciled:** 2026-08-20 (checked against upstream `main`)

## Checking for upstream updates

1. Diff upstream `claude/SKILL.md` and `references/` against this tree — most
   content maps 1:1 even though wording differs.
2. Look for **new capabilities** (e.g. the `aws3d` isometric library and the
   Allied Telesis hardware icons were added after the initial vendor), **new
   verified/broken stencil names**, and **new layout/quality rules**.
3. Port improvements into the local progressive-disclosure style rather than
   pasting upstream's monolith. Update "Last reconciled" above.

## Local deltas already ported from upstream

- 3D / isometric support: `references/aws-icons-3d.md`, `references/aws-icons-allied-telesis.md`, and the "3D / Isometric Diagrams" section in `SKILL.md`.
- "Layout self-check" (straight arrows / no-overlap checklist) in `SKILL.md`.
- Unmapped-service `general_AWScloud` fallback in `references/aws-icons-common.md`.
