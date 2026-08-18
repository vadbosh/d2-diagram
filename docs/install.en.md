# Installing

## What gets installed where

One directory per assistant, containing the skill and its references:

| Assistant | Path |
|---|---|
| Claude Code | `~/.claude/skills/d2-diagram/` |
| Opencode | `~/.config/opencode/skills/d2-diagram/` |
| Codex | `~/.codex/skills/d2-diagram/` |

The format is identical for all three, so installation is a plain directory
copy. Nothing outside `$HOME` is touched, and no shell profile is modified.

```bash
./install.sh
```

An assistant whose skills directory does not exist is reported as skipped. The
installer does not create it: an empty tree the assistant never reads is worse
than nothing, because it looks installed.

## Flags

| Flag | Effect |
|---|---|
| `--dry-run` | print every action, change nothing |
| `--ide claude` | install into one assistant only (`claude`, `opencode`, `codex`) |
| `--skills-dir D` | install into `D` instead of the detected location |
| `--with-d2` | install the d2 binary too, without asking |
| `--no-d2` | never touch the binary, only report whether it is there |
| `--bin-dir D` | put the binary in `D` instead of `~/.local/bin` |
| `-h`, `--help` | usage |

`--skills-dir` is for a non-standard layout — a portable checkout, a container
image, an assistant installed under a prefix.

## Re-running it

Idempotent. The installer compares the shipped skill with what is installed and
does nothing when they match:

```
[claude] already current — ~/.claude/skills/d2-diagram
[opencode] already current — ~/.config/opencode/skills/d2-diagram
[codex] already current — ~/.codex/skills/d2-diagram
```

When they differ, the existing copy is saved first — to
`~/.local/state/d2-skill-backups/<ide>-<timestamp>/`, and deliberately **not**
beside the skill.

The reason is specific rather than stylistic. An assistant reads the whole skill
directory, so a `SKILL.md.bak.1786446628` sitting next to `SKILL.md` is loaded as
part of the skill; a backup of an entire skill directory placed beside it is
loaded as a second skill. Both have happened in the wild. Override the location
with `D2_SKILL_BACKUP_DIR` if you keep backups elsewhere.

## The d2 binary

The skill writes `.d2` files; without the binary nothing renders. So a missing
binary is not just reported, it is offered:

```
d2 is NOT on PATH — the skill can write .d2 files but nothing will render.
Download and install the latest d2 into ~/.local/bin? [y/N]
```

Answer `y` and the installer resolves the newest release for this OS and
architecture, downloads the tarball, installs the binary into `~/.local/bin`
and prints the version it got. When the directory is not on `PATH`, it says so.

Nothing is downloaded silently:

- on a terminal you are asked, and the default is no;
- with no terminal — CI, a pipe, a provisioning script — nothing is fetched
  unless `--with-d2` was passed;
- `--no-d2` suppresses the offer entirely;
- `--dry-run` prints the exact URL it would fetch and stops.

Platform detection covers `linux` and `macos` on `amd64` and `arm64`; all four
archives were fetched from the current release and answer with HTTP 200, so the
names the installer builds are right. Anything else prints the releases page and
leaves the decision to you.

On macOS the installer prefers Homebrew when it finds it: `brew install d2`
currently gives 0.8.1, ahead of the newest GitHub release, because upstream
tagged v0.8.1 without attaching binaries to it. With no brew — or if brew fails
— it falls back to the release archive, which is 0.7.1.

That fallback was exercised on Linux by faking a Darwin host with a failing
brew: the script reported the failure, resolved `macos-arm64`, downloaded the
archive, and then refused it because the binary would not run on the machine —
`installed … but it does not run — wrong build for this machine?`. The brew
branch itself has never run on a real Mac.

The version is resolved from the GitHub *releases* endpoint, not from tags. A
tag can exist upstream with no binaries attached — `v0.8.1` is exactly that —
and building a download URL from it yields a 404.

Upstream publishes no checksums next to the tarballs, so there is nothing to
verify the download against; the transport is HTTPS to github.com and that is
the whole guarantee.

Upstream also publishes a `curl -fsSL https://d2lang.com/install.sh | sh -s --`
one-liner. Neither the installer nor this documentation uses it: piping a
downloaded script into a shell runs whatever the endpoint served that minute,
with no chance to read it first. What `--with-d2` does instead is the same three
steps you would run by hand, and you can run them by hand with `--no-d2`:

```bash
tag=$(curl -fsSL https://api.github.com/repos/terrastruct/d2/releases/latest \
      | sed -n 's/.*"tag_name" *: *"\([^"]*\)".*/\1/p' | head -1)
curl -fsSL -o d2.tar.gz \
  "https://github.com/terrastruct/d2/releases/download/$tag/d2-$tag-linux-arm64.tar.gz"
tar xzf d2.tar.gz
install -m 0755 "d2-$tag/bin/d2" ~/.local/bin/d2
```

Adjust `linux-arm64` to your platform: the assets are named `linux-amd64`,
`macos-amd64` and `macos-arm64`.

## Verifying

```bash
d2 --version                 # the binary
./tests/test_render.sh       # the examples still compile and hold their rules
```

Then start a **new** assistant session — a running one has already loaded its
skill list. Ask for something a diagram answers ("draw the module graph of this
package"); if the skill is live, the reply writes a `.d2` and renders a `.png`
rather than producing a Mermaid block.

## Removing

```bash
./uninstall.sh                     # from every assistant that has it
./uninstall.sh --dry-run
./uninstall.sh --ide codex
./uninstall.sh --skills-dir D      # from D, matching install.sh
./uninstall.sh --purge             # also delete the saved backups
```

Backups are kept unless `--purge` is given. The `d2` binary is left alone —
this repository did not install it.
