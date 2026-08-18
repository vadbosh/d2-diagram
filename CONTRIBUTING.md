# Contributing

Small repository, few rules. Most of them exist because breaking them produced
something that looked fine and was not.

## Language

English for commit messages, code comments and documentation.

Documentation ships in pairs: `README.md` / `README.RU.md`, and
`docs/<name>.en.md` / `docs/<name>.ru.md`. A change to one half is not finished
until the other half says the same thing.

The Russian version is not a line-by-line translation — it is the same content
written the way a Russian technical writer would write it. What must stay
identical is the *facts*: file names, flags, numbers, commands. Versions drift
apart on facts long before anyone notices the prose, so check them mechanically:

```bash
grep -c 'with-d2' README.md README.RU.md      # same count in both, or something is missing
```

## Commits

Conventional commits, as in the existing history:

```
feat:  new capability
fix:   a defect corrected
docs:  documentation only
chore: housekeeping, no behaviour change
```

Say *why* in the body, not what — the diff already says what. A message that
records the failure behind the change is worth more than a tidy summary; look at
`git log` here for the tone.

## Before a pull request

```bash
./tests/test_render.sh                                  # every example compiles and holds its rules
shellcheck install.sh uninstall.sh tests/test_render.sh  # no findings
```

`test_render.sh` skips itself when `d2` is absent — a skipped suite is not a
passing suite, so install the binary before claiming the tests pass.

## Rules specific to this repository

These four are easy to break without knowing, and each has been broken already:

**Commit the `.d2`, never the `.svg`.** SVG is a scratch step on the way to a
PNG and lives in `/tmp`. GitHub will not open an SVG file page, so a committed
one is unreachable, and it silently drifts once someone re-renders only the PNG.

**PNG belongs in `examples/` and nowhere else.** `.gitignore` enforces this. The
gallery is what a reader sees without installing anything; a PNG anywhere else
is build output.

**No `|md` blocks in a diagram.** A markdown label compiles to `<foreignObject>`,
and GitHub refuses to render the whole SVG containing one. Titles are plain
quoted strings with `\n` on a `shape: text` node. The test suite checks this.

**Never leave a backup inside `skill/`.** An assistant reads that directory
whole, so `SKILL.md.bak.1786446628` next to `SKILL.md` installs itself as part
of the skill — and a backup of the directory placed beside it loads as a second
skill. Both have happened on real machines. Put copies in
`~/.local/state/d2-skill-backups/` instead.

## Changing a diagram

Edit the `.d2`, re-render, and look at the picture before pushing it. A layout
engine produces surprising results from correct sources, and `d2` leaves a
partial file behind when it fails — so trust the exit code, not the presence of
output.

Check the aspect ratio of what you produced. A README column is about 900 px, so
anything past roughly 2:1 renders as an unreadable strip. Flipping `direction:`
between `right` and `down` usually fixes it in one word.

## Adding to the skill

`skill/SKILL.md` is loaded into an assistant's context on every trigger, so its
size is a running cost. Add a rule only when it changes what the assistant does,
and write the reason next to it — a rule without its failure gets weakened by
the next person who finds it inconvenient.
