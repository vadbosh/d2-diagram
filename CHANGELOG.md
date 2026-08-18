# Changelog

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
