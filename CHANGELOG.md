# Changelog

## 0.3.4 — 2026-08-22

### Added

- **The last three releases reached `docs/` — in both languages at once.**
  `SKILL.md` had them and the manuals did not, which is the drift that costs
  most: nobody re-reading the prose ever finds it.

  `design` gains "a defect that exists only in the output" — why an edge through
  a container title cannot be seen in the `.d2`, why choosing the other layout
  engine does not help, why reading the picture does not catch it either, and
  why the check ships inside `skill/` rather than beside the other scripts.
  Including what it cannot do: it reads geometry, so a diagram can pass it and
  still draw a dependency that does not exist.

  `install` gains "the rest of the toolchain" — `rsvg-convert`, Source Sans 3,
  ImageMagick and `fontTools`, what each one's absence actually costs, and why
  the installer reports them rather than installing them. With the `fontTools`
  story in full: Debian refuses `pip install` into the system Python, `pipx`
  installs applications rather than importable libraries, and
  `uv run --no-project --with fonttools` is what leaves nothing behind.

  Checked mechanically across all four EN/RU pairs — fifteen facts counted in
  both versions, zero divergence; no broken links or anchors outside code
  blocks; no stray characters; no real paths in the examples.

### Fixed

- **The toolchain report assumed Debian.** It printed `sudo apt install` on any
  system and named Debian packages, so on Fedora or macOS it was a command that
  does not exist naming packages that do not exist. The detection was always
  fine — it asks whether the *command* is there — so only the advice was wrong,
  which is the better half to have broken.

  Now: apt and Homebrew get an exact command, and everything else gets the plain
  list of what is missing plus a note that names differ per distribution. Only
  those two are filled in because only those two were tried; guessing at the
  rest reads as authority it has not earned. Homebrew takes two lines when the
  font is among the missing — it is a cask, and `brew install` will not take a
  cask and a formula together.

- **The font check reported "missing" where it could only say "cannot tell".**
  fontconfig is not a given: on macOS it arrives with librsvg rather than with
  the system, and a font installed through Font Book is invisible to it. With no
  `fc-list` the answer is now that it cannot tell, because a false alarm here
  sends someone installing a font they already have.

- **`printf '--cask …'` was read as an option**, so the Homebrew font name came
  out empty. Every name is emitted with `printf '%s'` now. Found by exercising
  the Homebrew branch by hand rather than assuming it was too simple to fail.

## 0.3.3 — 2026-08-22

### Fixed

- **The skill pointed at four things an installed copy does not have.** Only
  `SKILL.md`, `references/` and `scripts/` travel into an assistant, and the
  text referred to `render.sh` three times and to `examples/` once. An agent
  following it would reach for a file that is not there. The rasterizing
  procedure is spelled out inline instead, and the gallery is described rather
  than cited.

- **`release.sh` could not have caught that.** Its leak check knew about
  `install.sh`, `tests/` and the rest, but not `render.sh`, `examples/` or
  `lib/` — the three that had actually leaked. Added.

### Added

- **Switching the layout engine does not avoid the label collision.** Measured
  on 0.7.1 against a diagram built to collide: `dagre` and `elk` both draw the
  edge through the title. Worth saying, because the same document recommends
  `elk` for layered infrastructure and it reads like a lever here. It is not.

- **What the check cannot do.** It reads geometry. A picture can be flawless and
  still draw a dependency that does not exist, or miss the one that matters —
  which is what step 1 of the workflow is for, and the one part no tool
  verifies.

- **The table of corrections**, in one place: a title under an incoming edge, a
  column instead of a screenful, too many edges, the wrong thing standing out —
  and the source-level knob for each. D2 takes no coordinates by design, so a
  correction changes what the diagram says and lets the engine re-solve; the
  levers were scattered across four sections and are now also collected where
  the render is being judged.

## 0.3.2 — 2026-08-22

### Added

- **`scripts/check_labels.py` — the collision check, and it ships with the
  skill.** An edge drawn through a label survives compile, validate and
  rasterize; `d2 validate` cannot see it because it is not in the source. The
  script walks the SVG, measures every node and container label with the real
  font, and reports any edge path that crosses one — with the `magick` crop
  that shows it.

  It lives under `skill/` on purpose. Only `SKILL.md` and `references/` reach an
  installed skill, so a check kept in the repository would have been a check the
  agent drawing your diagram does not have.

  Widths use `fontTools`. Nothing is installed system-wide for it: Debian
  refuses `pip install` into the system Python (PEP 668), and
  `uv run --no-project --with fonttools` borrows the library from a cache
  instead. Without either, widths are estimated and the script says so — it
  degrades rather than lying.

- **`tests/fixtures/label-collision.d2`** and two cases in the suite: the
  gallery must be clean, and the planted collision must be found. The second is
  the one that matters. While being written this checker reported "nothing
  crossed" twice on files that were visibly broken — once because a regex could
  not follow nested `<g>`, once because an edge id arrives HTML-escaped so
  `-&gt;` never matched `->`. Both times it was cheerful about it.

### Fixed

- **Two more edges through container titles, in diagrams that had been read and
  called clean.** `cloud provider` in `cluster-request-path` and `PostgreSQL` in
  `ts-domain-model` — both crossed, both missed by eye at full-page scale, both
  found by the new check within a minute of it working. That is the argument for
  having it.

- **A font check that reported the opposite of the truth.** `fc-list | grep -q`
  under `set -o pipefail`: `grep -q` exits at the first match, `fc-list` takes
  SIGPIPE, the pipeline returns 141 and the `if` reads it as failure. The
  installer announced Source Sans 3 missing on a machine that had it, and the
  same shape sat in `render.sh` — working only because `fc-list : family` is
  short enough to finish first.

- **Step 4 of the workflow told you to run `render.sh`**, which is in the
  repository and not in an installed skill. It now carries the full sequence
  inline, `sed` included, which is what a skill without the repository around it
  needs.

### Changed

- `install.sh` reports the rest of the toolchain — `rsvg-convert`, Source Sans 3,
  ImageMagick, and how `fontTools` will be reached — with the `apt` line for
  whatever is missing. It reports rather than installs: these are system
  packages and this installer writes only into `$HOME`. Until now it checked for
  `d2` alone, and a machine with d2 and nothing else produced no picture, or a
  wrong one, and the skill looked like the thing at fault.

## 0.3.1 — 2026-08-22

### Fixed

- **Two of the four gallery diagrams shipped with an arrow drawn through a
  container's title.** D2 centres a container label on its top border and
  `dagre` routes an incoming edge into the top of that same container, so the
  two collide. In `cluster-request-path` the arrow replaced the em-dash in
  `Kubernetes — namespace gateway-system` and read as punctuation; in
  `ts-monorepo` two dashed edges straddled `outside the repository` and clipped
  the last letter.

  Fixed in the sources: a shorter title plus `label.near: top-left` for the
  first, a shorter title for the second — where two edges straddle the centre,
  moving the label into a corner walks it into one of them.

- **The claim that the font override flags do nothing was wrong.** Measured
  again, one flag at a time: `--font-bold` and `--font-italic` are applied and
  their subsets end up embedded; `--font-regular` does nothing *ever*, because
  D2 emits no regular face at all — bold and italic are the only two
  `@font-face` blocks, and plain text carries no `font-family`. Passing bold,
  italic and semibold without regular gives a file byte-identical to passing all
  four. Shape labels are set in bold, which is why bold is the flag that counts.

  The earlier note went from "all four together or it silently falls back" to
  "none of them work". Neither was right, and the table now says which is which.

- **The by-hand rasterizing recipe substituted only the regular class**, which
  is the one class a typical diagram does not use. Following it left every label
  in librsvg's fallback font — losing the weight and outgrowing the boxes, the
  exact failure the surrounding paragraph warns about. It now repoints all four
  classes and restates weight and slant, matching what `render.sh` has been
  doing all along. Step 4 of the workflow points at `render.sh` instead of a
  one-liner that skips the step.

### Added

- **"Reading the render"** — what to look at once the PNG exists, since `d2
  validate` sees none of it. The container-title collision and its three fixes,
  the habit of cropping a strip at 1:1 before judging (at full-page scale a 2 px
  arrow crossing a label is invisible), and the shorter list of defects that
  follow it.

## 0.3.0 — 2026-08-20

### Changed

- **`render.sh` rasterizes with `rsvg-convert` instead of a headless browser.**
  The old path was never a choice, it was a workaround: D2's own PNG export
  downloads a Playwright driver, and that download is now dead on every platform
  — `playwright.azureedge.net` is retired, and the host that replaced it answers
  with a redirect the Go client inside D2 does not follow, so pointing
  `PLAYWRIGHT_DOWNLOAD_HOST` at it turns the 404 into a 400. The previous note
  blaming `linux/arm64` was too narrow. librsvg needs no browser and no driver
  cache, and the SVG's own `viewBox` sets the canvas, so there is no window to
  size. A headless browser stays as the fallback, and `D2_BROWSER` still forces
  it.
- **The scratch SVG is repointed at an installed font before rasterizing.**
  librsvg ignores the `@font-face` data URLs D2 embeds, so left alone it
  measured the labels in DejaVu and they stopped fitting the boxes D2 had sized
  — `unit_price_cents` ran into `bigint` in the gallery. What D2 embeds is a
  cut-down Source Sans Pro renamed per diagram, so no fontconfig alias can catch
  it; `render.sh` rewrites the four text classes to `$D2_SANS` (default
  `Source Sans 3`) and refuses to run when that font is absent rather than
  producing a quietly wrong picture.
- **The gallery was re-rendered** through the new path. Same pixel dimensions as
  the browser produced, RMSE 4–6% from antialiasing, no layout shift.

## 0.2.0 — 2026-08-18

The release that stopped taking its own word for things. Every capability the
documentation described was run, and the ones that could not be run are now
labelled as such instead of reading like experience.

### Added

- **`release.sh`** — one command that checks the three records of a version
  against each other: `version:` in the skill, the section in this changelog,
  and the git tag. It found the first bug it was written for: the skill shipped
  `1.0` while the changelog announced `0.1.0`.
- **`D2_MIRRORS`** — a colon-separated list of directories holding a copy of the
  skill that `install.sh` does not write, such as a config canon that
  redistributes it. `release.sh check` compares them and fails on a stale one.
- **Homebrew on macOS.** The installer now prefers `brew install d2` when it
  finds brew, because the formula carries 0.8.1 against the newest GitHub
  release of 0.7.1 — upstream tagged v0.8.1 without attaching binaries.
- **`uninstall.sh --skills-dir`**, matching the installer. Being able to put a
  skill somewhere and not take it away was a worse deal than having no flag.
- **A gallery of four diagrams** with source and picture side by side —
  Terraform roots, a Kubernetes request path, a TypeScript package graph, and
  types drawn against the tables behind them.
- **`CONTRIBUTING.md`**, whose fourth section is the reason it exists: the four
  rules of this repository that are easy to break without knowing.

### Changed

- **The README leads with Install and Use.** A reader who has just landed wants
  to run it, not to read its design principles.
- **Prompts a person would type**, replacing prose that described what to ask
  for. Terraform gets its own section, because there the graph already exists
  and nobody should be reading `.tf` files by eye to draw it.

### Verified, and written down as measured

- **Every shape 0.7.1 accepts**, tested one at a time. `triangle` is not one:
  it is an arrowhead value only.
- **Multi-board files write a directory**, `out/index.svg` plus
  `out/scenarios/<name>.svg`, not the single file the rest of the skill assumes.
- **`terraform graph`** run on a nine-line provider-free module, its DOT output
  reproduced in the README so any reader can repeat it without a cloud account.
- **The dependency extractors installed and pointed at real code.** madge read a
  TypeScript project — 541 modules, 1129 edges — while dependency-cruiser,
  installed globally, returned `"modules": []` for the same project and asked to
  be a local devDependency; it handled plain JavaScript correctly. `pydeps`
  wants a path, not a module name. `pyreverse` writes two `.dot` files into the
  working directory rather than to stdout.
- **The macOS archives exist** — all four release tarballs answer HTTP 200 — and
  the installer's fallback was exercised by faking a Darwin host with a failing
  brew, which also proved the "wrong build for this machine" guard.

### Corrected

- **`inframap` was recommended and never used.** Replaced with `terraform state
  list` and `terraform show -json`, which ship with Terraform and were run here.
  It survives as one line marked as a pointer to a third-party tool.
- **The custom-font flags do nothing visible on 0.7.1.** There are eight of them,
  not four; a missing path is rejected, but a valid TTF — two of them, by flag
  and by environment variable — rendered a byte-identical SVG. Treat a custom
  family as unavailable until verified on your own build.
- **Terms used without explanation**: `dagre` and `elk` are the two layout
  engines inside the binary, `foreignObject` is the SVG element that embeds
  HTML, `viewBox` is where D2 records the canvas size.
- **macOS is no longer claimed as tested.** The binaries exist and the installer
  has a code path; nobody has run it on a Mac.

## 0.1.0 — 2026-08-18

First release. Everything here came out of one working session — diagramming a
live EKS repository — so the entries read as what was learned rather than as a
feature list.

### Added

- **The skill.** `SKILL.md` plus four working examples: a Terraform layer graph,
  a code module and class graph, a data model, and the shared theme.
- **A palette in one file.** Tailwind slate with a blue spine and an orange
  accent, imported by every diagram via `...@theme`. The class roster is
  semantic — `spine`, `focus`, `ext`, `dep`, `read`, `cut` — so a diagram stays
  readable when the palette changes underneath it.
- **Installer** for Claude Code, Opencode and Codex. Idempotent, `--dry-run`,
  per-assistant install, and it offers to fetch the `d2` binary for the current
  OS and architecture.
- **Test suite.** Compiles every shipped example, asserts none produces a
  `<foreignObject>`, validates the theme, and checks that every documented style
  class exists.

### Learned the hard way

- **A `|md` label makes GitHub reject the whole SVG.** Markdown compiles to
  `<foreignObject>`; the file page then answers "Unable to render code block" on
  both tabs, and the diagram never appears. Titles are plain strings on a
  `shape: text` node. Dropping markdown also halved the file size, because D2
  stops embedding the italic and mono font subsets.
- **PNG is what gets committed, SVG is a scratch step.** An embedded SVG is
  visible but cannot be enlarged, since the click lands on that same unrenderable
  page. The README embeds a PNG wrapped in a link to itself; SVG is written to
  `/tmp` on the way to the raster and never committed.
- **Aspect ratio decides whether a diagram is readable.** A README column is
  about 900 px, so a 4.6:1 canvas is a decorative strip. One `direction:` change
  turned 3521×770 into 1128×2060.
- **`classes` is a reserved word**, and naming a container that produces the
  misleading `is an invalid class field, must be reserved keyword`.
- **A backup beside a skill installs itself as part of the skill.** Assistants
  read the whole directory. The installer writes backups to
  `~/.local/state/d2-skill-backups/` for exactly that reason.
- **D2's own PNG export can fail for reasons outside the diagram** — on
  linux/arm64 it tries to fetch a Playwright driver that 404s. The documented
  fallback is a headless-browser screenshot of the scratch SVG.

### Deliberately not included

- A Windows installer.
- Anything that positions by coordinate or area — Venn, pyramid, radar,
  treemap, charts. D2 cannot do those, and the documentation says so instead of
  pretending otherwise.
