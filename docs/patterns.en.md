# Patterns and traps

## Getting the edges from the code, not from memory

A dependency graph drawn from recollection is wrong the day someone adds an
import. Extract it.

**Terraform.** The graph between root modules is already written down — every
cross-root read is a `terraform_remote_state` block:

```bash
rg -n 'data "terraform_remote_state" "' --glob 'ext.data.tf' .   # edges
rg -o 'resource "helm_release" "[a-z0-9_-]+"' <layer>/*.tf        # what each installs
rg -n 'module "' <layer>/*.tf                                     # modules per root
```

One container per root, three to five leaf nodes for what it owns, one edge per
remote-state read. Apply order and coupling then read off the picture.

**Code.**

| Stack | Extractor | Run here? |
|---|---|---|
| JS / TS | `madge --json --extensions ts,tsx src` | yes — 541 modules, 1129 edges on a real project |
| JS / TS | `depcruise --output-type json --no-config src` | yes, with a catch (below) |
| Python modules | `pydeps <path-to-package> --show-deps --no-output --no-show` | yes |
| Python classes | `pyreverse -o dot -p NAME <path>` (ships with pylint) | yes — 51 modules, 94 imports |
| Go | `go list -deps ./...`, `go mod graph` | yes |
| Java | `jdeps -verbose:class app.jar` | no JDK here |
| PHP | `deptrac analyse --formatter=json` | no composer here |

Each emits JSON or dot; convert the edges into D2 lines and let the engine lay
them out.

Four traps, each met while running these:

**dependency-cruiser installed globally returns an empty graph for TypeScript.**
`"modules": []`, and it says why: it wants to be a local devDependency so it can
reach the project's transpilers. The same global binary handled plain JavaScript
correctly — 2 modules, 1 edge — so an empty result is a setup problem, not an
answer. madge, also global, read the same TypeScript project without complaint.

**`madge --circular` is the one that finds cycles**; `--json` gives the graph and
says nothing about them. Both are worth running.

**pydeps wants a path, not a module name.** `pydeps json` answers
`No such file or directory: 'json'`; point it at the package directory instead.

**pyreverse writes two files**, `classes_<name>.dot` and `packages_<name>.dot`,
into the working directory rather than to stdout. A package with no classes
leaves the first one empty, which looks like failure and is not.

`go mod graph` printing nothing is the same kind of non-failure: it lists *module*
requirements, and a module with no external ones has none. `go list -deps ./...`
is the one that answers about packages — 123 of them for a two-import module.

**Live infrastructure.** When the question is "what is actually deployed" rather
than "what does the code say", start from the state — `terraform state list` for
the inventory, `terraform show -json` for the attributes and the dependency
edges between resources. Both ship with Terraform.

Third-party tools such as `inframap` render a provider-aware graph straight from
a tfstate. They may suit you; they were not used to build anything in this
repository, so treat that as a pointer rather than a recommendation.

## Cutting nodes

The commonest way an infrastructure diagram becomes unreadable is the uniform
edge. Every Terraform root writes to the same S3 backend, so seven arrows into
one "S3 backend" box say exactly what one line of subtitle says, while costing
seven crossings. Same for "AWS" wrappers around everything, a "user" actor at
the left edge, and per-resource IAM roles.

Target: one screen, no crossing edges, under about 25 leaf nodes. More than that
is two diagrams.

## Shapes worth knowing

```d2
db: {shape: cylinder}          # storage
q: {shape: queue}              # queue or stream
c: {shape: cloud}              # something managed elsewhere
t: {shape: text}               # a label with no box — titles use this
```

Also `class` and `sql_table` (below), `sequence_diagram`, `person`, `hexagon`,
`package`, `step`, `callout`, `stored_data`.

## Class and data-model diagrams

```d2
Record: {
  shape: class
  +zone_id: str
  +to_change_batch(): dict
  -validate(): bool
}
Client -> Record: returns
```

```d2
dns_record: {
  shape: sql_table
  id: bigint {constraint: primary_key}
  zone_id: varchar(32) {constraint: foreign_key}
  set_identifier: varchar(64) {constraint: unique}
}
route53_zone.id <-> dns_record.zone_id: "1 : N"
```

An edge can attach to a specific column — that is what makes a foreign key
readable rather than a line between two boxes.

## Traps

**`|md` blocks are banned, everywhere.** A markdown label compiles to
`<foreignObject>`, and GitHub refuses to render an SVG containing one — the file
page shows "Unable to render code block" and the picture never appears. Write
the title as a plain quoted string with `\n` on a `shape: text` node.

**`classes` is a reserved word.** Name a container `classes` and everything
inside it is parsed as a style-class definition. The error is misleading:
`... is an invalid class field, must be reserved keyword`. Same care with
`vars`, `layers`, `scenarios`, `steps`, `direction`.

**A method signature is parsed.** Brackets in a return type break the file:
`list[Record]` fails. Quote it — `"list of Record"` — or simplify.

**`;` is a statement separator.** An unquoted label containing one splits into
two nodes. Quote any label with punctuation in it.

**Trust the exit code, not the file.** D2 leaves a partial render behind when it
fails, so "the file exists" proves nothing.

**PNG export can fail on the machine, not in the diagram.** `d2 x.d2 x.png`
downloads a Playwright driver first, and that download is dead on every
platform: `playwright.azureedge.net` is retired, and the host that replaced it
answers with a redirect the Go client inside D2 does not follow. Render an SVG
into `/tmp` and rasterize it with `rsvg-convert` (librsvg, `apt install
librsvg2-bin`):

```bash
d2 cluster.d2 /tmp/cluster.svg
rsvg-convert -z 2 /tmp/cluster.svg -o docs/diagrams/cluster.png
```

**librsvg has to be pointed at the font.** D2 embeds the font as a data URL in
`@font-face`, which librsvg ignores; it then measures the labels in whatever
sans it happens to have, and they stop fitting the boxes D2 sized for them —
under DejaVu, `unit_price_cents` ran into `bigint`. What D2 embeds is a cut-down
Source Sans Pro carrying only the glyphs used, renamed per diagram, so install a
Source Sans (`apt install fonts-adobe-sourcesans3`) and repoint the four text
classes at it before rasterizing. `render.sh` does this: the family name is
quoted only in the class rules and never in the `@font-face` blocks, which is
what makes a `sed` safe here.

**A headless browser still works.** `render.sh` uses one when there is no
librsvg, and `D2_BROWSER` forces that path. It is only the heavier way round — a
whole browser for one conversion.

**ImageMagick is not a substitute.** `convert x.svg x.png` "works" and drops
every CSS fill, producing a grayscale image — useless for checking a diagram.

**Look at the render before reporting it.** An unread diagram is not a verified
diagram; layout engines produce surprising results from correct sources.
