#!/usr/bin/env bash
# Install the d2-diagram skill — Linux / macOS.
#
# The skill teaches an assistant to draw diagrams as D2 source rendered to PNG,
# so the picture lives in git next to the code that it describes.
#
#   ./install.sh                  install into every assistant found
#   ./install.sh --dry-run        print what would happen, change nothing
#   ./install.sh --ide claude     install into one assistant only
#   ./install.sh --skills-dir D   install into D instead of the detected location
#   ./install.sh --with-d2        also install the d2 binary, without asking
#   ./install.sh --no-d2          never install the binary, only report it
#   ./install.sh --bin-dir D      put the binary in D instead of ~/.local/bin
#
# Idempotent: re-running rewrites only what differs. An existing copy of the
# skill is saved to ~/.local/state/d2-skill-backups/<ide>-<timestamp>/ first —
# never beside the skill itself, because an assistant reads that whole directory
# and would load the backup as part of the skill.
#
# The skill is useless without the d2 binary, so a missing one is offered for
# installation: the latest release is taken from GitHub for this OS and
# architecture. On a terminal you are asked first; without one, nothing is
# downloaded unless --with-d2 was given. Nothing outside $HOME is touched.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SRC/skill"
BACKUP_ROOT="${D2_SKILL_BACKUP_DIR:-$HOME/.local/state/d2-skill-backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"

DRY_RUN=0
ONLY_IDE=""
SKILLS_DIR=""
BIN_DIR="${D2_BIN_DIR:-$HOME/.local/bin}"
WANT_D2=ask          # ask | yes | no

usage() {
	sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1 ;;
		--ide) ONLY_IDE="${2:-}"; shift ;;
		--skills-dir) SKILLS_DIR="${2:-}"; shift ;;
		--with-d2) WANT_D2=yes ;;
		--no-d2) WANT_D2=no ;;
		--bin-dir) BIN_DIR="${2:-}"; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

say() { printf '%s\n' "$*"; }
run() {
	if [ "$DRY_RUN" -eq 1 ]; then
		say "  would: $*"
	else
		"$@"
	fi
}

# Where each assistant keeps user-authored skills. A directory that does not
# exist means that assistant is not installed, and it is skipped rather than
# created — creating it would leave an empty tree the assistant never reads.
skills_dir_for() {
	case "$1" in
		claude) printf '%s\n' "$HOME/.claude/skills" ;;
		opencode) printf '%s\n' "$HOME/.config/opencode/skills" ;;
		codex) printf '%s\n' "$HOME/.codex/skills" ;;
		*) return 1 ;;
	esac
}

dirs_differ() {
	# Returns 0 when the installed copy differs from the source.
	local src="$1" dst="$2"
	[ -d "$dst" ] || return 0
	! diff -r -q "$src" "$dst" >/dev/null 2>&1
}

install_into() {
	local ide="$1" root dst backup
	if [ -n "$SKILLS_DIR" ]; then
		root="$SKILLS_DIR"
	else
		root="$(skills_dir_for "$ide")"
	fi

	if [ ! -d "$root" ]; then
		say "[$ide] skipped — $root does not exist"
		return 0
	fi

	dst="$root/d2-diagram"
	if ! dirs_differ "$SKILL_SRC" "$dst"; then
		say "[$ide] already current — $dst"
		return 0
	fi

	if [ -d "$dst" ]; then
		backup="$BACKUP_ROOT/$ide-$STAMP"
		say "[$ide] backing up the existing skill to $backup"
		run mkdir -p "$BACKUP_ROOT"
		run cp -a "$dst" "$backup"
		# Guard the only destructive step: refuse anything whose path is not the
		# skill directory itself, however $root was arrived at.
		case "$dst" in
			*/d2-diagram) run rm -rf "$dst" ;;
			*) echo "refusing to delete $dst — not a d2-diagram directory" >&2; exit 2 ;;
		esac
	fi

	say "[$ide] installing into $dst"
	run mkdir -p "$dst"
	run cp -a "$SKILL_SRC/." "$dst/"
	INSTALLED=$((INSTALLED + 1))
}

if [ ! -f "$SKILL_SRC/SKILL.md" ]; then
	echo "no skill found at $SKILL_SRC — run this from a checkout of the repository" >&2
	exit 2
fi

if [ -n "$ONLY_IDE" ] && ! skills_dir_for "$ONLY_IDE" >/dev/null 2>&1; then
	echo "unknown assistant: $ONLY_IDE (expected claude, opencode or codex)" >&2
	exit 2
fi

INSTALLED=0
if [ -n "$ONLY_IDE" ]; then
	install_into "$ONLY_IDE"
else
	for ide in claude opencode codex; do
		install_into "$ide"
	done
fi

# --- the d2 binary -----------------------------------------------------------
# The skill writes .d2 files; without the binary nothing renders, so a missing
# one is worth more than a warning at the end of the output.

d2_platform() {
	# Prints "<os>-<arch>" as used in the release asset names, or fails.
	local os arch
	case "$(uname -s)" in
		Linux) os=linux ;;
		Darwin) os=macos ;;
		*) return 1 ;;
	esac
	case "$(uname -m)" in
		x86_64|amd64) arch=amd64 ;;
		aarch64|arm64) arch=arm64 ;;
		*) return 1 ;;
	esac
	printf '%s-%s\n' "$os" "$arch"
}

d2_latest_tag() {
	# The newest tag that actually carries release assets. A tag can exist
	# upstream with no binaries attached (v0.8.1 did), and downloading from it
	# gives a 404 — so ask the releases endpoint, not the tags one.
	local api='https://api.github.com/repos/terrastruct/d2/releases/latest'
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$api" 2>/dev/null | sed -n 's/.*"tag_name" *: *"\([^"]*\)".*/\1/p' | head -1
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "$api" 2>/dev/null | sed -n 's/.*"tag_name" *: *"\([^"]*\)".*/\1/p' | head -1
	fi
}

install_d2() {
	local plat tag url tmp
	# On macOS Homebrew is both shorter and ahead: the formula carried 0.8.1
	# while the newest GitHub *release* was 0.7.1, because upstream tagged
	# v0.8.1 without attaching binaries to it. Prefer it when it is there.
	#
	# NOT TESTED: this repository was built on Linux and no Mac was available.
	# The branch is written from the documented behaviour of `brew install`;
	# if it misbehaves, `--no-d2` plus `brew install d2` by hand is the escape.
	if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
		say "Homebrew found — installing d2 from the formula (usually newer than the release)"
		if [ "$DRY_RUN" -eq 1 ]; then
			say "  would: brew install d2"
			return 0
		fi
		if brew install d2; then
			say "installed $(command -v d2 || echo d2) ($(d2 --version 2>/dev/null || echo '?'))"
			return 0
		fi
		say "brew install failed — falling back to the release archive"
	fi

	if ! plat="$(d2_platform)"; then
		say "cannot pick a d2 build for $(uname -s)/$(uname -m) — install it by hand:"
		say "  https://github.com/terrastruct/d2/releases"
		return 1
	fi
	if ! command -v curl >/dev/null 2>&1 && ! command -v tar >/dev/null 2>&1; then
		say "curl and tar are needed to fetch d2 — install them, or install d2 by hand"
		return 1
	fi

	tag="$(d2_latest_tag || true)"
	if [ -z "$tag" ]; then
		say "could not reach the GitHub releases API — install d2 by hand:"
		say "  https://github.com/terrastruct/d2/releases"
		return 1
	fi

	url="https://github.com/terrastruct/d2/releases/download/$tag/d2-$tag-$plat.tar.gz"
	say "downloading d2 $tag for $plat"
	say "  $url"
	if [ "$DRY_RUN" -eq 1 ]; then
		say "  would: install into $BIN_DIR/d2"
		return 0
	fi

	tmp="$(mktemp -d)"
	# Upstream publishes no checksums next to the tarballs, so there is nothing
	# to verify against; the transport is HTTPS to github.com and that is all.
	if ! curl -fsSL -o "$tmp/d2.tar.gz" "$url"; then
		say "download failed — install d2 by hand: https://github.com/terrastruct/d2/releases"
		rm -rf "$tmp"
		return 1
	fi
	# The tarballs are built on macOS and carry xattr headers GNU tar does not
	# know, so it prints a warning per file. That noise is expected; anything
	# else tar says is not, and is passed through.
	if ! tar xzf "$tmp/d2.tar.gz" -C "$tmp" 2>"$tmp/tar.err"; then
		say "unpacking failed:"
		sed 's/^/  /' "$tmp/tar.err" >&2
		rm -rf "$tmp"
		return 1
	fi
	grep -v 'LIBARCHIVE.xattr' "$tmp/tar.err" >&2 || true

	if [ ! -x "$tmp/d2-$tag/bin/d2" ]; then
		say "the archive did not contain d2-$tag/bin/d2 — install it by hand"
		rm -rf "$tmp"
		return 1
	fi

	mkdir -p "$BIN_DIR"
	install -m 0755 "$tmp/d2-$tag/bin/d2" "$BIN_DIR/d2"
	rm -rf "$tmp"

	if ! "$BIN_DIR/d2" --version >/dev/null 2>&1; then
		say "installed $BIN_DIR/d2 but it does not run — wrong build for this machine?"
		return 1
	fi
	say "installed $BIN_DIR/d2 ($("$BIN_DIR/d2" --version 2>/dev/null))"
	case ":$PATH:" in
		*":$BIN_DIR:"*) ;;
		*) say "note: $BIN_DIR is not on PATH — add it to your shell profile" ;;
	esac
}

# ── the rest of the toolchain ───────────────────────────────────────────────
# d2 alone writes an SVG and stops. Everything that turns that into a PNG a
# reader can look at lives outside this repository, and until now nothing said
# so: the skill mentioned `apt install` in prose and the installer never
# checked. A machine that had d2 and nothing else produced no picture at all,
# or a picture with the wrong font metrics, and the failure looked like the
# skill being wrong.
#
# Reported, not installed. These are system packages and this installer writes
# only into $HOME — it is not going to call apt behind your back.
check_toolchain() {
	local missing=""

	if command -v rsvg-convert >/dev/null 2>&1; then
		say "rsvg-convert found: $(command -v rsvg-convert)"
	else
		say "rsvg-convert MISSING — render.sh cannot rasterize without it"
		missing="$missing librsvg2-bin"
	fi

	# Not `grep -q` here: it exits on the first match, fc-list gets SIGPIPE,
	# and `pipefail` turns the pipeline's status into 141 — so the check
	# reported the font missing on a machine that had it.
	if fc-list 2>/dev/null | grep -i 'source sans 3' >/dev/null; then
		say "Source Sans 3 found"
	else
		say "Source Sans 3 MISSING — librsvg ignores the font D2 embeds and"
		say "  falls back to whatever sans it has, so labels outgrow their boxes"
		missing="$missing fonts-adobe-sourcesans3"
	fi

	if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
		say "ImageMagick found"
	else
		say "ImageMagick MISSING — needed to crop a strip and read it at 1:1,"
		say "  which is how the defects that survive rendering get caught"
		missing="$missing imagemagick"
	fi

	# The label checker measures text with fontTools. Debian refuses
	# `pip install` into the system Python (PEP 668), so uv is the path that
	# needs nothing installed: `uv run --with fonttools` uses a cached
	# throwaway environment. Without either, the checker estimates widths and
	# says so — it degrades, it does not break.
	if python3 -c 'import fontTools' >/dev/null 2>&1; then
		say "fontTools importable — the label check measures text exactly"
	elif command -v uv >/dev/null 2>&1; then
		say "uv found — the label check gets fontTools through it, nothing installed"
	else
		say "neither fontTools nor uv — the label check will estimate widths"
		say "  (apt install python3-fonttools, or install uv)"
	fi

	if [ -n "$missing" ]; then
		say ""
		say "install the missing ones:  sudo apt install$missing"
	fi
}

say ""
check_toolchain

say ""
if command -v d2 >/dev/null 2>&1; then
	say "d2 found: $(command -v d2) $(d2 --version 2>/dev/null || true)"
else
	say "d2 is NOT on PATH — the skill can write .d2 files but nothing will render."
	case "$WANT_D2" in
		yes)
			install_d2 || true
			;;
		no)
			say "Install it yourself, or re-run with --with-d2."
			;;
		ask)
			if [ -t 0 ]; then
				printf 'Download and install the latest d2 into %s? [y/N] ' "$BIN_DIR"
				read -r reply
				case "$reply" in
					[yY]|[yY][eE][sS]) install_d2 || true ;;
					*) say "skipped — install it later with: ./install.sh --with-d2" ;;
				esac
			else
				say "Not a terminal, so nothing was downloaded."
				say "Run ./install.sh --with-d2 to fetch the latest release."
			fi
			;;
	esac
fi

if [ "$DRY_RUN" -eq 1 ]; then
	say "dry run — nothing was changed"
elif [ "$INSTALLED" -eq 0 ]; then
	say "nothing to do — every assistant already had the current skill"
else
	say "installed into $INSTALLED assistant(s); start a new session to pick it up"
fi
