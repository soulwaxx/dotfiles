# Styling Reference

Icon sizing, style templates, edge styling, the title block, and XML well-formedness. Service stencil names live in the `aws-icons-*.md` category files; the two-icon-pattern rule, group containers, base template, and PNG background fix live in [aws-icons-common.md](aws-icons-common.md).

## Icon Style

- Icon size: **78x78px** for main services, **65x65px** for secondary.
- Use `sketch=0` on all icons.
- Font size: **12px** for labels.
- **NO colored backgrounds** on group boxes — always `fillColor=none`.
- `strokeColor` depends on the icon pattern (`#ffffff` for service-level `resourceIcon`, `none` for resource-level standalone shapes) — see the two-icon-pattern rule in [aws-icons-common.md](aws-icons-common.md).

## Style templates

**resourceIcon** (78x78, colored square frame), substitute `<COLOR>` and `<SERVICE>`:

```
sketch=0;points=[[0,0,0],[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0,0],[0,1,0],[0.25,1,0],[0.5,1,0],[0.75,1,0],[1,1,0],[0,0.25,0],[0,0.5,0],[0,0.75,0],[1,0.25,0],[1,0.5,0],[1,0.75,0]];outlineConnect=0;fontColor=#232F3E;fillColor=<COLOR>;strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.<SERVICE>
```

**productIcon** (70x100, taller with service header bar), substitute `<SERVICE>`:

```
sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=#ffffff;fillColor=#232F3E;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.productIcon;prIcon=mxgraph.aws4.<SERVICE>
```

## Edge Style — critical for clean diagrams

**Base edge style:**

```
edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;html=1;strokeWidth=2;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;
```

**Edge label rules:**

- Keep labels SHORT (1-2 words max). Detail goes in icon labels, not edge labels.
- Always add `labelBackgroundColor=#F5F5F5;fontSize=11;` to edges with labels.
- For edges WITHOUT labels: omit `value` entirely.
- When NOT to label: if the flow is obvious (Lambda → DynamoDB doesn't need "Write").

**For edges to services ABOVE or BELOW main flow, use explicit exit/entry points** (prevents draw.io routing lines through other icons):

- Exit bottom: `exitX=0.5;exitY=1;exitDx=0;exitDy=0;`
- Enter top: `entryX=0.5;entryY=0;entryDx=0;entryDy=0;`

**Edge types:**

- Solid (`strokeWidth=2`): primary data flow
- Dashed (`strokeWidth=2;dashed=1;`): optional/async
- Red dashed (`strokeWidth=2;dashed=1;strokeColor=#DD344C;`): error path

**Edge attachment (fixes the "green cross" problem):**

- Every edge MUST have both `source="<cell-id>"` and `target="<cell-id>"` referencing valid cell IDs.
- NEVER create floating/unattached edges — bind every edge to shapes at both ends.
- Always include `exitX/exitY` and `entryX/entryY` to define exact connection points on the shape perimeter.
- Cross-container edges: when source and target are in different containers, set the edge's `parent="1"`.
- Every edge MUST have `<mxGeometry relative="1" as="geometry" />` as a child.

## Numbered flow edges (non-technical mode)

Show flow order with circled numbers instead of technical labels:

- Flow A: ① → ② → ③ → ④ (white circled numbers)
- Flow B: ❶ → ❷ → ❸ → ❹ (black circled numbers for a second flow)

Use edge labels: `value="①"` with `fontSize=14;fontStyle=1;labelBackgroundColor=#ffffff;`

## Title block

Place top-left, after the background rectangle:

```xml
<mxCell value="&lt;b&gt;Diagram Title&lt;/b&gt;&lt;br&gt;Author | Date | Version" style="text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;rounded=0;fontSize=14;spacing=8;" vertex="1" parent="1">
  <mxGeometry x="40" y="30" width="420" height="60" as="geometry" />
</mxCell>
```

## XML well-formedness

- **NEVER include XML comments (`<!-- -->`)** — they cause parse errors.
- Escape special characters: `&amp;` `&lt;` `&gt;` `&quot;`.
- Always use unique `id` values for each mxCell.
- Every edge MUST have `<mxGeometry relative="1" as="geometry" />` as a child.
- Root structure requires cells `id="0"` (root) and `id="1"` (default layer, `parent="0"`). The full base template is in [aws-icons-common.md](aws-icons-common.md).
