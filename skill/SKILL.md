---
name: d2-diagram
description: Draw architecture, dependency, class, network and flow diagrams as D2 source rendered to PNG. Use when asked to draw, diagram, visualize or map anything structural — infrastructure (Terraform layers, EKS/VPC topology, Kubernetes workloads, CI pipelines, request paths) as well as code (module and import graphs, class relations, call flows, data models, state machines) — when a diagram must live in git next to the code, or when Mermaid output looks too crude for the destination. Also use to redraw an existing Mermaid or Graphviz dot source at higher quality.
license: MIT
metadata:
  version: "0.3.4"
  base: adapted from github.com/fmind/dotfiles/tree/main/skills/d2 (MIT)
---

# D2 diagrams

D2 is a diagram scripting language: text in, picture out, layout computed by the engine.
Never place coordinates by hand — describe containment and edges, let the layout engine solve it.
Both engines ship inside the binary: `dagre` (the Dagre directed-graph library, the default) and
`elk` (Eclipse Layout Kernel, layered algorithm). `d2 layout` prints them.

**Two files per diagram, and only two: `<name>.d2` and `<name>.png`.** SVG is never a deliverable
here and never gets committed — see [What ships](#what-ships) before rendering anything.

`d2` is installed at `/usr/local/bin/d2` (v0.7.1). It writes an SVG and stops; everything that turns
that into a picture a reader can look at is a separate package —
`apt install librsvg2-bin fonts-adobe-sourcesans3 imagemagick`. Check before drawing, not after —
a missing one of these does not fail loudly, it produces a picture with the wrong font metrics.

`scripts/check_labels.py` measures text with `fontTools`. Where it is not importable, run the
script under `uv run --no-project --with fonttools`: that borrows the library without installing
it, which matters because Debian refuses `pip install` into the system Python (PEP 668).

## Choose the tool first

| Situation | Tool |
|---|---|
| Diagram lives in git, changes with the code, destination is GitHub README/PR | **D2** |
| Must render natively inside a GitLab MR comment or issue body | Mermaid (` ```mermaid `), GitLab bundles mermaid 11.13 + layout-elk |
| One-off editorial figure for a client deck or a marketing page | `diagram-design` skill, if installed |
| Graph must be derived from real state, not from reading code | `terraform state list` + `terraform show -json`, then draw that |

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
   sed -E \
     -e 's/font-family: "d2-[0-9]+-font-regular"/font-family: "Source Sans 3"/' \
     -e 's/font-family: "d2-[0-9]+-font-bold"/font-family: "Source Sans 3"; font-weight: 700/' \
     -e 's/font-family: "d2-[0-9]+-font-italic"/font-family: "Source Sans 3"; font-style: italic/' \
     /tmp/cluster.svg > /tmp/cluster.fixed.svg
   rsvg-convert -z 2 /tmp/cluster.fixed.svg -o docs/diagrams/cluster.png
   ```

   The `sed` is not optional and not cosmetic — [Rasterizing](#rasterizing--png-export-is-broken-on-this-box)
   is why. Skip it and every label falls back to librsvg's own sans: the weight is gone and the
   text outgrows the boxes D2 sized for it.

5. **Trust the exit code, not the presence of the file** — D2 leaves a partial render after an error.
6. Look at the PNG before reporting it. An unread diagram is not a verified diagram — and look at
   it the way [Reading the render](#reading-the-render) says to, because the defects that survive
   this far are the ones a whole-page view hides.

## Reading the render

A diagram that compiles, validates and rasterizes can still be wrong, and the wrongness is never in
the `.d2` — it is in what the layout engine did with it. `d2 validate` cannot see any of this.

**Look at the top edge of every container.** This is where the one recurring defect lives: D2 centres
a container's title on its top border, and `dagre` routes an incoming edge into the top of that same
container. The two collide, and the arrow is drawn straight through the title. Two of the four
two diagrams in the gallery this skill comes from shipped like that — in one, the arrow replaced
the em-dash in `Kubernetes — namespace gateway-system` and read as punctuation.

Switching the layout engine does not help. Measured on 0.7.1 against a diagram built to collide:
`dagre` and `elk` both draw the edge through the title. `elk` is worth trying for other reasons —
see [Syntax](#syntax-that-covers-most-infra-diagrams) — but not for this.

The collision happens when the title still occupies the horizontal middle of the container, which is
where the edge comes in. So:

- **Short titles.** A title narrower than half the container leaves the middle free. `cloud provider`
  never collided; `Kubernetes — namespace gateway-system` always did.
- **`label.near: top-left`** moves the title into the corner — but only helps if the title is short
  enough not to reach the middle anyway. Both together is what fixed the example.
- **Two incoming edges** straddle the centre instead of hitting it, so a centred title gets clipped
  from both sides. There the fix is the title, not its position.

**Check it mechanically. Do not rely on your eye for this one.** The check ships with the skill:

```bash
python3 scripts/check_labels.py /tmp/cluster.svg
# or, where fontTools is not importable and uv is:
uv run --no-project --with fonttools python3 scripts/check_labels.py /tmp/cluster.svg
```

It names the label, the edge crossing it, and the `magick` crop that shows it. Exit 1 means
something crosses. Run it on the scratch SVG, before the PNG is worth looking at.

Widths come from the real font when `fontTools` is importable and from an estimate when it is not;
the estimate is deliberately narrow, so a missing dependency loses findings rather than inventing
them. It says which mode it used on stderr.

The check exists because reading the picture is not reliable. Two collisions in the gallery of the
repository this skill comes from were looked at directly and called clean; the checker found them in
the same files minutes later. At full-page scale a 2 px arrow crossing a label is invisible.

**For everything the checker does not cover, crop before you judge:**

```bash
magick diagram.png -crop 1400x140+120+1930 +repage /tmp/check.png   # w x h + x + y
```

Also worth a look, in order of how often they bite: labels touching or crossing the border of their
own box; edges that pass under an unrelated container instead of around it; and a label sitting on
top of another where two edges converge. And the aspect ratio: divide the `viewBox` width by its
height, and a number far from 1 is the cue to flip `direction:`, as
[Aspect ratio](#rendering-and-destination) explains.

**Nothing here tells you the diagram is true.** The check reads geometry; a picture can be
flawless and still draw a dependency that does not exist, or miss the one that matters. That is
what step 1 of the [Workflow](#workflow) is for — read the source, never memory — and it is the one
part no tool verifies.

**Corrections are descriptive, because D2 is.** There is no way to nudge a box: you change what the
diagram says and let the engine re-solve. The whole set of levers:

| What went wrong | What to change |
|---|---|
| title under an incoming edge | shorter title, `label.near: top-left`, usually both |
| a column instead of a screenful | `direction: right` ↔ `down` |
| too many edges to follow | fewer nodes, or two diagrams — see [Node budget](#node-budget) |
| the wrong thing stands out | a different `class` — `spine`, `focus`, `zone` |

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

Fonts stay D2's bundled defaults — Source Sans Pro for text, Source Code Pro for monospace — and
that is what every example here was rendered with.

There are eight override flags (`--font-regular`, `-italic`, `-bold`, `-semibold` and the same four
with `-mono`), each with its own `D2_FONT_*` variable. They do work — but not evenly. Measured on
0.7.1, one flag at a time, on a two-node diagram:

| flag | effect on the SVG |
|---|---|
| `--font-regular`, `D2_FONT_REGULAR` | **none, ever** — byte-identical output |
| `--font-bold` | applied, and this is the one that matters |
| `--font-italic` | applied |
| `--font-semibold` | none here — nothing in the sample was semibold |
| a path that does not exist | rejected outright: `failed to read font at …` |

`--font-regular` is not a partial set falling back silently, it has nothing to act on. D2 emits
**only two** `@font-face` blocks, bold and italic; there is no regular face at all, and plain text
carries no `font-family`. Passing bold, italic and semibold *without* regular produces a file
byte-identical to passing all four.

Bold is the flag that counts, because D2 sets shape labels in it — every label carries
`class="text-bold"`. Substituting it swaps the embedded WOFF subset for one cut from your file
(4488 → 12592 bytes in the measured case).

None of it reaches a PNG by itself. librsvg does not read those embedded faces, so a custom family
lands in the SVG and vanishes from the picture unless the class rules are repointed first — see
[Rasterizing](#rasterizing--png-export-is-broken-on-this-box).

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

Shapes accepted by 0.7.1, all checked against the binary: `rectangle`, `square`, `page`,
`parallelogram`, `document`, `cylinder`, `queue`, `package`, `step`, `callout`, `stored_data`,
`person`, `diamond`, `oval`, `circle`, `hexagon`, `cloud`, `text`, `code`, `class`, `sql_table`,
`sequence_diagram`. `triangle` is not one of them — it is only an arrowhead.

`layers`/`scenarios`/`steps` put several boards in one file. Note what that does to the output: it
writes a *directory*, `out/index.svg` plus `out/scenarios/<name>.svg`, not the single file the rest
of this skill assumes.

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
so the pipeline is `.d2` → scratch `.svg` → `rsvg-convert` → `.png`. Write that SVG under `/tmp` and let
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

Render the PNG at 2× so the full-size click is sharp: `rsvg-convert -z 2` on the scratch SVG.

### Rasterizing — PNG export is broken on this box

`d2 x.d2 x.png` fails: it tries to fetch a Playwright driver from `playwright.azureedge.net`, a host
Microsoft has retired. The replacement (`cdn.playwright.dev/dbazure/download/playwright`) answers
`307` to `playwright.download.prss.microsoft.com`, and the `playwright-go` downloader inside D2 does
not follow that redirect — pointing `PLAYWRIGHT_DOWNLOAD_HOST` at it turns the `404` into a `400`,
not into a working driver. Measured 2026-08-20 on `linux-amd64`; the older note blaming `arm64` was
too narrow, the driver URL is dead for every platform. Do not retry it, and do not report it as a D2
bug.

The whole procedure is four steps: `d2` to a scratch SVG in `/tmp`, repoint the fonts,
`rsvg-convert -z 2`, PNG next to the source. No browser, no Playwright cache, no headless flags.

`-z 2` is the 2× scale that keeps the full-size click sharp — it replaces the browser's
`--force-device-scale-factor=2`, and unlike the browser path it needs no window size, because the
SVG's own `viewBox` sets the canvas.

**librsvg has to be pointed at the font, or the labels lose their weight and outgrow their boxes.**
D2 embeds the font as a data URL in `@font-face`; librsvg ignores those and measures the text in
whatever sans it has, so the labels stop fitting the boxes D2 sized for them — under DejaVu,
`unit_price_cents` ran into `bigint`. What D2 embeds is a cut-down Source Sans Pro carrying only the
glyphs used, renamed per diagram (`d2-<hash>-font-bold`), so no fontconfig alias can catch it.

Two things go wrong at once, and the second is the one that gets missed: shape labels are set in
**bold**, so substituting only the regular class leaves every label in librsvg's fallback. Repoint
all four classes, and restate the weight and the slant — in D2's own faces they live inside the font
file, not in the CSS, so they are lost the moment the family changes:

```bash
apt install fonts-adobe-sourcesans3 librsvg2-bin
d2 cluster.d2 /tmp/cluster.svg
sed -E \
  -e 's/font-family: "d2-[0-9]+-font-regular"/font-family: "Source Sans 3"/' \
  -e 's/font-family: "d2-[0-9]+-font-bold"/font-family: "Source Sans 3"; font-weight: 700/' \
  -e 's/font-family: "d2-[0-9]+-font-italic"/font-family: "Source Sans 3"; font-style: italic/' \
  -e 's/font-family: "d2-[0-9]+-font-mono"/font-family: "monospace"/' \
  /tmp/cluster.svg > /tmp/cluster.fixed.svg
rsvg-convert -z 2 /tmp/cluster.fixed.svg -o docs/diagrams/cluster.png
```

The family name is quoted only in the class rules and never in the `@font-face` blocks, which is
what makes that `sed` safe. All four expressions, every time — the one that is easy to drop is
`-font-bold`, and it is the one that matters, because D2 sets shape labels in bold.

Checked against the old browser render of the same source: identical pixel dimensions, RMSE 4–6%
from antialiasing alone, no layout shift.

This is the one legitimate use of SVG in this skill. It never reaches the repository.

Then `Read` the PNG to actually look at it. Two rasterizers that are **not** substitutes:
`convert`/ImageMagick drops all CSS fills and produces a grayscale image; a headless Chromium
screenshot works but pulls a browser onto the box for one conversion — use it only where a
Playwright cache already exists.

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
