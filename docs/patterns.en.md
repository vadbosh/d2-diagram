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

| Stack | Extractor |
|---|---|
| JS / TS | `madge --json src/`, `depcruise --output-type json` |
| Python modules | `pydeps --show-deps --no-output pkg/` |
| Python classes | `pyreverse -o dot pkg/` (ships with pylint) |
| Go | `go mod graph`, `go list -deps ./...` |
| Java | `jdeps -verbose:class app.jar` |
| PHP | `deptrac analyse --formatter=json` |

Each emits JSON or dot; convert the edges into D2 lines and let the engine lay
them out.

Only the Go pair was run here: `go list -deps ./...` returned 123 packages for a
two-import module, and `go mod graph` printed nothing for it — correct, since it
lists *module* requirements and a module with no external ones has none. Reach
for `go list` when the question is packages.

**The rest were not run** — none of madge, dependency-cruiser, pydeps, pyreverse,
jdeps or deptrac is installed here. They are named so that you reach for an
extractor instead of guessing at imports; check the flags against each tool's own
documentation.

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
downloads a Playwright driver; on linux/arm64 that download currently 404s.
Render an SVG into `/tmp` and screenshot it with a headless browser instead:

```bash
d2 cluster.d2 /tmp/cluster.svg
chrome --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=2400,1000 \
  --screenshot=docs/diagrams/cluster.png "file:///tmp/cluster.svg"
```

**ImageMagick is not a substitute.** `convert x.svg x.png` "works" and drops
every CSS fill, producing a grayscale image — useless for checking a diagram.

**Look at the render before reporting it.** An unread diagram is not a verified
diagram; layout engines produce surprising results from correct sources.
