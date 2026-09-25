---
name: aws-architecture-diagram
disable-model-invocation: true
description: Always use when user asks to create, generate, or build an AWS architecture diagram, cloud infrastructure diagram, or system diagram with AWS services. Also activates for draw.io diagrams mentioning AWS services like Lambda, DynamoDB, S3, API Gateway, etc.
---

# AWS Architecture Diagram Skill

Generate AWS architecture diagrams as native `.drawio` files using official AWS Architecture Icons. Optionally export to PNG, SVG, or PDF with embedded XML (so exported files remain editable in draw.io).

This core file holds the workflow, layout, and the failure-prone rules every diagram needs. Depth lives in `references/` loaded on demand.

## How to create a diagram

1. **Generate draw.io XML** in mxGraphModel format, following the layout and critical rules below, stencil names from the `aws-icons-*.md` category catalog, and styling from [styles.md](references/styles.md).
2. **Write the XML** to a `.drawio` file using the Write tool.
3. **Two-step review** — export to PNG ([export.md](references/export.md)), inspect the image for empty/broken icons, overlapping edges, and misaligned labels, fix the XML, and re-export. This catches rendering problems (wrong stencil names, broken styles) that are invisible in raw XML.
4. **If the user requested an export format** (png, svg, pdf), export using the draw.io CLI — see [export.md](references/export.md).
5. **Open the result** with `open` (macOS), `xdg-open` (Linux), or print the path.

## Layout Rules

- **Left-to-right flow** for data/request path: **UI/Frontend on the LEFT**, **data sources / external systems on the RIGHT**.
- Use horizontal lanes for parallel paths (top lane, bottom lane).
- **Minimum 220px horizontal spacing** between icons (room for edge labels); **minimum 250px vertical spacing** between lanes.
- Secondary/auxiliary services (monitoring, DLQ) go BELOW main flow with a 280px+ gap.
- Canvas: `pageWidth="2400" pageHeight="1400"`, viewport `dx="2800" dy="1600"`.
- Always include a title block top-left, after the background rectangle — XML in [styles.md](references/styles.md).

## Layout self-check — straight arrows, no overlaps

Correct icons on a messy layout still read as unprofessional. These rules are deliberately concrete/checkable, not "make it look nice". Verify every diagram against them before finishing.

- **Align nodes to a consistent axis so edges are single, straight segments.** Keep the horizontal or vertical delta between adjacent nodes in a flow constant (same lane y-coordinate, same column spacing) so edges render as one clean line, not a dogleg.
- **Align branch/secondary nodes on the exact centerline of their parent.** Compute `child.x = parent.center_x - child.width/2`; don't eyeball it. A few pixels of drift turns a "straight down" edge into a visible diagonal.
- **One bend maximum per edge, ideally zero.** If a path needs more than one bend to avoid an obstacle, the layout is wrong — move the node, don't add bends.
- **No edge may cross an unrelated icon's bounding box.** Before finalizing, check each edge's path against every icon's `(x, y, width, height)` it isn't connected to; if it would cross, move the node or add explicit exit/entry points.
- **No two edges may overlap or visually merge.** Offset parallel flows between the same lanes with different exit/entry points or a waypoint so there's a visible gap.
- **Minimize edge crossings.** Order nodes in the direction data actually flows; route unavoidable crossings (feedback/response paths) with a visible offset.
- **Keep spacing consistent, not just "enough."** Use the same minimum step size between every adjacent pair — mixed 400px/250px gaps read as sloppy even when nothing overlaps.
- **Balance the composition.** Size the canvas to actual content plus a consistent margin; don't leave one half dense and the other empty.
- **Self-check:** after placing coordinates, trace each edge source→target and verify (1) no icon crossing, (2) no edge overlap, (3) ≤1 bend, (4) endpoints flush with their icons. Fix the layout, not just the intent, if any check fails.

## Critical Rules — prevent broken diagrams

The most failure-prone points. Full edge styling lives in [styles.md](references/styles.md); stencil names in the `aws-icons-*.md` category catalog.

- **No floating edges (the "green cross").** Every edge MUST have both `source="<cell-id>"` and `target="<cell-id>"` referencing valid cell IDs, plus explicit `exitX/exitY` and `entryX/entryY`.
- **Cross-container edges:** when source and target sit in different containers, set the edge's `parent="1"`.
- **Containers group correctly:** every group/boundary shape includes `container=1;dropTarget=1;`, and child cells set `parent="<boundary-cell-id>"` with geometry relative to the parent, not the canvas.
- **Never guess a stencil name.** A wrong `resIcon`/`shape` renders as an empty square — verify against the `aws-icons-*.md` category catalog. If a service is in no reference file, use the labeled `general_AWScloud` fallback (never a plain colored rectangle) — see [aws-icons-common.md](references/aws-icons-common.md).
- **Well-formed XML:** no XML comments (they cause parse errors); escape `&amp;` `&lt;` `&gt;` `&quot;`; unique `id` per cell; root needs `id="0"` and `id="1"` (default layer, `parent="0"`).

## Audience Mode

Before generating, assess the target audience:

- **Technical**: service names, protocol labels (HTTPS, gRPC), CIDR blocks, instance types.
- **Non-technical**: action labels ("Store Data", "Send Notification"), implementation details hidden, numbered flow (① ② ③) — see [styles.md](references/styles.md) for circled-number edges.

If unclear, ask: "Technical audience or executive/non-technical?"

## 3D / Isometric Diagrams

If the user asks for a **3D**, **isometric**, or "AWS 3D" diagram, do NOT fake it by placing flat `aws4` icons on hand-built platform/pedestal shapes. draw.io has a real, separate built-in library: `mxgraph.aws3d.*`.

- Load [aws-icons-3d.md](references/aws-icons-3d.md) before picking any icon — it holds the verified shape table (camelCase names, e.g. `dynamoDb`), style prefix, sizes, `isometricEdgeStyle` edge templates, and a coverage-gap table.
- This is a legacy pre-2019 set with **much smaller coverage** than `aws4` (no API Gateway, ECS/EKS/Fargate, Step Functions, EventBridge, SNS, Aurora, CloudWatch, IAM, etc.). Check the gap table before assuming an icon exists, and flag substitutions to the user rather than guessing.
- For generic hardware (clients, on-prem servers, racks, switches) with no AWS icon, see [aws-icons-allied-telesis.md](references/aws-icons-allied-telesis.md) — a bundled isometric image library that fills that gap.
- These icons are already 3D — arrange them in an ascending isometric staircase (diagonal offsets between nodes); don't add fake platforms underneath.
- Use `edgeStyle=isometricEdgeStyle` (with `endArrow=block` override for reliable arrowheads) instead of `orthogonalEdgeStyle` for connectors.

## Companion Guide

After generating the `.drawio` file, also generate a markdown guide — same filename with `.md` extension — containing the diagram title, flow description (numbered steps), service list with purpose, and key design decisions.

## Reference Files

Progressive disclosure — essentials here, depth on demand.

**Icon catalog** — service stencil names, colors, broken icons, renamed-service gotchas, group containers, the two-icon-pattern rule, base template, and PNG background fix. Pick the category file:

- [aws-icons-common.md](references/aws-icons-common.md) — standalone shapes, group containers, the two-icon-pattern rule, base template, PNG background fix.
- [aws-icons-compute.md](references/aws-icons-compute.md), [database](references/aws-icons-database.md), [storage](references/aws-icons-storage.md), [networking](references/aws-icons-networking.md), [security](references/aws-icons-security.md), [integration](references/aws-icons-integration.md) (incl. productIcon/SQS), [analytics-ml](references/aws-icons-analytics-ml.md), [iot-migration-devtools](references/aws-icons-iot-migration-devtools.md) — per-service stencil names and colors.
- [aws-icons-3d.md](references/aws-icons-3d.md), [aws-icons-allied-telesis.md](references/aws-icons-allied-telesis.md) — the separate `aws3d` isometric library and bundled generic-hardware images, for 3D/isometric diagrams only.

**Workflow depth:**

- [styles.md](references/styles.md) — icon sizing, style templates, full edge styling (labels, exit/entry points, edge types, attachment), title block, numbered-flow edges, and XML well-formedness.
- [export.md](references/export.md) — draw.io CLI per platform, formats and flags, multi-page diagrams, and the pre-export validation checklist.
