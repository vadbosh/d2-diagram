---
name: d2-diagram
description: Draw architecture, dependency, class, network and flow diagrams as D2 source rendered to PNG. Use when asked to draw, diagram, visualize or map anything structural — infrastructure (Terraform layers, EKS/VPC topology, Kubernetes workloads, CI pipelines, request paths) as well as code (module and import graphs, class relations, call flows, data models, state machines) — when a diagram must live in git next to the code, or when Mermaid output looks too crude for the destination. Also use to redraw an existing Mermaid or Graphviz dot source at higher quality.
license: MIT
metadata:
  version: "0.1.0"
  base: adapted from github.com/fmind/dotfiles/tree/main/skills/d2 (MIT)
---

# D2 diagrams

D2 is a diagram scripting language: text in, picture out, layout computed by the engine.
Never place coordinates by hand — describe containment and edges, let `dagre`/`elk` solve it.

**Two files per diagram, and only two: `<name>.d2` and `<name>.png`.** SVG is never a deliverable
here and never gets committed — see [What ships](#what-ships) before rendering anything.

`d2` is installed at `/usr/local/bin/d2` (v0.7.1, linux/arm64).

## Choose the tool first

| Situation | Tool |
|---|---|
| Diagram lives in git, changes with the code, destination is GitHub README/PR | **D2** |
| Must render natively inside a GitLab MR comment or issue body | Mermaid (` ```mermaid `), GitLab bundles mermaid 11.13 + layout-elk |
| One-off editorial figure for a client deck or a marketing page | `diagram-design` skill, if installed |
| Graph must be derived from real state, not from reading code | `inframap generate <tfstate> \| dot -Tsvg`, then optionally redraw in D2 |

D2 when the diagram is a maintained artifact. Mermaid when the renderer is not yours.

## Workflow

1. Read the real source before drawing: `.tf` files, `terraform_remote_state` blocks, k8s manifests, `helm_release` names. Never draw from memory of what the stack probably looks like.
2. State the thesis in one line — what the reader must see. Everything that does not serve it gets cut.
3. Write the smallest readable `.d2`. Containers over arrows, short labels over sentences.
4. Format, validate, render to a scratch SVG, then rasterize (see [Rendering](#rendering-and-destination)):

   ```bash
   d2 fmt cluster.d2
   d2 validate cluster.d2
   d2 cluster.d2 /tmp/cluster.svg     # scratch only — /tmp, never the repo
   ```

5. **Trust the exit code, not the presence of the file** — D2 leaves a partial render after an error.
6. Look at the PNG before reporting it. An unread diagram is not a verified diagram.

## Node budget

Cut a node when it carries no information. The commonest offender in infra diagrams is the
uniform edge: every Terraform root writes to the same S3 backend, so seven arrows to one
"S3 backend" box say nothing that one line of subtitle does not. Same for "AWS" wrappers,
"user" actors, and per-resource IAM roles.

Target: one screen, no crossing edges, under ~25 leaf nodes. More than that means two diagrams.

## Brand tokens

Tailwind slate + `blue-700` accent, orange-600 for the one thing under change.
Neutral, familiar, prints fine, reads on the white GitHub background.

**Put the tokens in a `theme.d2` beside the diagrams and import it** — `...@theme` on the first line.
One file then restyles every diagram in the repo. A ready copy lives in
[`references/theme.d2`](references/theme.d2); it is the file used by the worked example.

Class roster: `spine` (solid blue, the 1-2 nodes read first), `zone` / `zone-warm` (large container:
white field, accent border), `layer` (ordinary grouping box), `focus` / `hot` (orange, what is
changing), `comp` (leaf), `store` (cylinder), `ext` (outside this stack), and for edges `dep`
(hard dependency), `read` (dashed blue, data read), `cut` (orange, the new path), `gone` (grey
dashed, being drained).

**A solid fill belongs on small boxes only.** Filling a container that wraps ten nodes floods the
diagram — use `zone` there: white inside, thick accent border, accent title.

**Never use an `|md ... |` block — not on nodes, not on the title.** Two separate reasons:

- On a node it renders as one flat wide strip and wrecks the row rhythm.
- Anywhere in the file it compiles to `<foreignObject>`, and **GitHub refuses to render an SVG that
  contains one** — the file page shows "Unable to render code block" on both the Code and the
  Preview tab, and the image will not appear in a README either. Verified on a private repo,
  GitHub web UI, D2 v0.7.1.

Write the title as a plain quoted string with `\n`, on a `shape: text` node so it gets no border:

```d2
title: "cluster-a — example-sandbox (us-east-1)\nSubtitle line, no backticks — plain text only." {
  shape: text
  near: top-center
  style: {font-size: 20; bold: true; font-color: "#0f172a"}
}
```

Dropping the markdown also drops the italic and mono font subsets D2 embeds for it: the four
diagrams in the worked example went from ~68 KB to ~39 KB each.

Two traps when converting a title to a plain string: `;` is a statement separator, so an unquoted
label containing one splits into two nodes; and without `shape: text` the title gets a box drawn
around it.

The tokens, if writing the preamble by hand:

```d2
vars: {
  d2-config: {
    layout-engine: elk
    theme-id: 0
    pad: 40
  }
}

classes: {
  layer: {                      # ordinary grouping box
    style: {fill: "#f8fafc"; stroke: "#cbd5e1"; stroke-width: 2; font-color: "#0f172a"; border-radius: 6}
  }
  base: {                       # accent — the 1-2 things read first
    style: {fill: "#eff6ff"; stroke: "#2563eb"; stroke-width: 2; font-color: "#0f172a"; border-radius: 6}
  }
  comp: {                       # leaf component inside a box
    style: {fill: "#ffffff"; stroke: "#94a3b8"; font-color: "#334155"; border-radius: 4}
  }
  ext: {                        # something outside this stack's control
    style: {fill: "#f1f5f9"; stroke: "#64748b"; stroke-dash: 3; font-color: "#475569"}
  }
  dep: {                        # hard dependency / apply order
    style: {stroke: "#94a3b8"; stroke-width: 2; font-color: "#64748b"}
  }
  read: {                       # data read, soft coupling
    style: {stroke: "#2563eb"; stroke-width: 2; stroke-dash: 4; font-color: "#2563eb"}
  }
}
```

Reference values: paper `#f8fafc`, ink `#0f172a`, muted `#64748b`, rule `#cbd5e1`, accent `#2563eb`, accent-fill `#eff6ff`.

Fonts stay D2's bundled defaults. A custom family needs real TTF files passed as
`--font-regular/--font-bold/--font-italic/--font-semibold` together — a partial set silently falls back.

## Syntax that covers most infra diagrams

```d2
title: "cluster-a — example-sandbox (us-east-1)\nSubtitle on its own line. Plain text — no markdown, no backticks." {
  shape: text
  near: top-center
  style: {font-size: 20; bold: true}
}

vpc: "1.VPC" {
  class: base
  sub: k8s subnets {class: comp}
}

svc: "3.EKS-SERVICES" {
  class: layer
  alb: aws-load-balancer-controller {class: comp}
}

vpc -> svc: applied first {class: dep}
ext -> svc: read while flag = false {class: read}
```

Useful extras: `shape: cylinder|queue|cloud|package|hexagon`, `direction: right`, `sql_table` for
data models, `near: top-center` for pinned labels, `layers`/`scenarios`/`steps` for a before/after pair
in one file.

`d2 themes` lists built-in theme IDs, `d2 layout` lists engines. In 0.7.1 only `dagre` (default) and
`elk` are bundled; `elk` is usually better for layered infra, `dagre` for trees and flows.

## Rendering and destination

### What ships

| File | Role | Committed |
|---|---|---|
| `<name>.d2` | the source, the only thing anyone edits | yes |
| `<name>.png` | what every reader actually looks at | yes |
| `theme.d2` | shared colors and line styles, one per diagram directory | yes |
| `*.svg` | scratch step on the way to the PNG, lives in `/tmp` | **no** |

**SVG is not a deliverable — it is an intermediate.** The only reason it exists at all is that D2's
own PNG export is broken on this box (see [Rasterizing](#rasterizing--png-export-is-broken-on-this-box)),
so the pipeline is `.d2` → scratch `.svg` → screenshot → `.png`. Write that SVG under `/tmp` and let
it die there. Where `d2 x.d2 x.png` works directly, there is no SVG at all.

Two reasons it must not be committed, both hit in practice:

- **GitHub will not open an SVG file page.** Embedded in a README the picture appears, but a click
  lands on "Unable to render code block", so a reader can see a thumbnail and never enlarge it.
- **It goes stale silently.** The next person re-renders the PNG and forgets the SVG; now two files
  claim to be the same diagram and one of them lies.

Embed the PNG wrapped in a link to itself — the click then opens it full size in GitHub's viewer:

```markdown
[![Cluster A](docs/diagrams/cluster-a.png)](docs/diagrams/cluster-a.png)
```

If someone genuinely needs a vector — a print, a slide deck — render one on the spot from the `.d2`
into `/tmp` and hand it over. Do not add it to the repository "just in case".

A PR diff of the `.d2` is readable; that is the whole point over a hand-written SVG.

**Aspect ratio decides whether the thumbnail is useful.** A README column is roughly 900 px, so a
2:1 canvas already renders text at a third of its size and a 4:1 one is unreadable. Check the
`viewBox` after rendering and flip `direction:` (`right` ↔ `down`) until the ratio is near 1:1 —
on the worked example that turned 4.57:1 into 0.55:1 with a one-word change.

Render the PNG at 2× so the full-size click is sharp: `--force-device-scale-factor=2` with a window
matching the `viewBox` of the scratch SVG.

### Rasterizing — PNG export is broken on this box

`d2 x.d2 x.png` fails: it tries to fetch a Playwright driver from `playwright.azureedge.net`,
which returns 404 for `linux-arm64`. Do not retry it, and do not report it as a D2 bug.

Render a scratch SVG **into `/tmp`**, screenshot it with the Chromium already in the Playwright
cache, keep the PNG, drop the SVG:

```bash
d2 cluster.d2 /tmp/cluster.svg
$HOME/.cache/ms-playwright/chromium-1228/chrome-linux/chrome \
  --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=2400,1000 \
  --screenshot=docs/diagrams/cluster.png "file:///tmp/cluster.svg"
```

This is the one legitimate use of SVG in this skill. It never reaches the repository.

Then `Read /tmp/shot.png` to actually look at it. `convert`/ImageMagick also "works" but drops all
CSS fills and produces a grayscale image — useless for checking a diagram.

`--window-size` sets the canvas; too small crops, too large leaves whitespace. Iterate once.

## Code, not only infrastructure

Nothing here is infra-specific — the language draws whatever the nodes are named after. For code use
`shape: class` (fields and methods with `+`/`-` visibility) and `shape: sql_table` for a data model:

```d2
Record: {
  shape: class
  +zone_id: str
  +to_change_batch(): dict
  -validate(): bool
}
Client -> Record: returns
```

**Never name a container `classes`** — it is the reserved keyword for the style-class block, and every
child inside is then parsed as a class definition. The error is misleading: `... is an invalid class
field, must be reserved keyword`. Same care with `vars`, `layers`, `scenarios`, `steps`, `direction`.

A method signature is parsed, so brackets in a return type break it: `list[Record]` fails, quote it
(`"list of Record"`) or simplify.

For a data model use `shape: sql_table`. Columns are `name: type`, and the constraint tag renders as
a right-hand marker (`PK`, `FK`, `UNQ`). Edges may attach to a specific column, which is what makes
the foreign key readable:

```d2
dns_record: {
  shape: sql_table
  id: bigint {constraint: primary_key}
  zone_id: varchar(32) {constraint: foreign_key}
  set_identifier: varchar(64) {constraint: unique}
}
route53_zone.id <-> dns_record.zone_id: "1 : N"
```

Worked example: [`references/example-data-model.d2`](references/example-data-model.d2).

## What D2 cannot draw

The dividing line is simple: **D2 places nodes with a layout engine, so anything where the meaning
lives in a coordinate or an area is out of reach.** No amount of styling gets around it.

| Works natively | Needs a grid hack | Not possible |
|---|---|---|
| architecture, flow, sequence, state, class, ER | quadrant / 2×2 matrix (`grid-rows`, `grid-columns`) | Venn — circles cannot be made to overlap |
| tree, org chart, nested containers, layer stack | comparison matrix | radar / spider |
| swimlane, process, data flow, request path | calendar-ish grids | pyramid, funnel — there is no triangle shape |
| cycles and feedback loops | | bar, line, scatter, gantt — no chart primitives, no axes |
| | | treemap — areas cannot be made proportional |

`shape: triangle` fails outright: `invalid shape, can only set "triangle" for arrowheads`.

For those, reach for something else: the `diagram-design` skill if it is installed (it writes SVG by
hand, which is why it can do pyramids and Venns), or `dataviz` for anything that is genuinely a chart
over data. Do not spend an hour bending D2 into a funnel.

Read the code first, then draw — but let a tool find the edges instead of guessing at imports:

| Stack | Extractor |
|---|---|
| JS / TS | `madge --json src/`, or `depcruise --output-type json` |
| Python modules | `pydeps --show-deps --no-output pkg/` |
| Python classes | `pyreverse -o dot pkg/` (ships with pylint) |
| Go | `go mod graph`, `go list -deps ./...` |
| Java | `jdeps -verbose:class app.jar` |
| PHP | `deptrac analyse --formatter=json` |

Each emits JSON or dot; convert the edges to D2 lines and lay them out. That keeps the graph honest —
a hand-drawn import graph is wrong the day someone adds an import.

## Terraform-specific recipe

The dependency graph is written down already — extract it instead of guessing:

```bash
rg -n 'data "terraform_remote_state" "' --glob 'ext.data.tf' .   # edges between roots
rg -o 'resource "helm_release" "[a-z0-9_-]+"' <layer>/*.tf        # what each layer installs
rg -n 'module "' <layer>/*.tf                                     # modules per root
```

One container per Terraform root, leaf nodes for the 3-5 things it owns, edges for
`terraform_remote_state` reads. Apply order and coupling then read off the picture.

A worked example against a real layered EKS stack is in
[`references/example-terraform-layers.d2`](references/example-terraform-layers.d2).
