# Export & Validation Reference

How to export `.drawio` files and the checklist to run before exporting.

## Validation — run before export

After generating XML, verify:

1. Every `resIcon=` value exists in the `aws-icons-*.md` category files.
2. Service-level icons have `strokeColor=#ffffff`.
3. Resource-level icons have `strokeColor=none`.
4. No XML comments present.
5. All cell IDs are unique.
6. Every edge has `<mxGeometry relative="1" as="geometry" />`.
7. No icon uses a guessed stencil name — all verified against the `aws-icons-*.md` category files.
8. Every edge has both `source` and `target` attributes referencing valid cell IDs (no floating edges).
9. All group/boundary shapes include `container=1;dropTarget=1;` in their style.
10. Children inside boundaries use `parent="<boundary-id>"` (not `parent="1"`).

## Multi-page diagrams

For complex architectures, use multiple pages in one `.drawio` file:

```xml
<mxfile>
  <diagram id="overview" name="Overview">...</diagram>
  <diagram id="networking" name="Networking Detail">...</diagram>
  <diagram id="data-flow" name="Data Flow">...</diagram>
</mxfile>
```

- Page 1: high-level overview (service-level icons only).
- Page 2+: detail views (resource-level icons, subnet layouts, etc.).

## Export CLI

For PNG/SVG/PDF export using the draw.io Desktop CLI:

| Platform | CLI Path |
|----------|----------|
| macOS | `/Applications/draw.io.app/Contents/MacOS/draw.io` |
| Linux | `drawio` (on PATH via snap/apt) |
| Windows | `"C:\Program Files\draw.io\draw.io.exe"` |

```bash
<CLI> -x -f <format> -e -b 10 -o <output> <input>
```

Flags: `-x` export, `-f` format (png/svg/pdf), `-e` embed diagram XML, `-b 10` border.

Exported files use a double extension: `name.drawio.png` — signals embedded XML, re-editable in draw.io.
