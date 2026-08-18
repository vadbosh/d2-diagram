#!/usr/bin/env bash
# Remove the d2-diagram skill — Linux / macOS.
#
#   ./uninstall.sh                remove from every assistant that has it
#   ./uninstall.sh --dry-run      print what would happen, change nothing
#   ./uninstall.sh --ide claude   remove from one assistant only
#   ./uninstall.sh --skills-dir D remove from D instead of the detected location
#   ./uninstall.sh --purge        also delete the backups under ~/.local/state/d2-skill-backups
#
# The d2 binary is left alone: this script did not install it.
set -euo pipefail

BACKUP_ROOT="${D2_SKILL_BACKUP_DIR:-$HOME/.local/state/d2-skill-backups}"

DRY_RUN=0
ONLY_IDE=""
SKILLS_DIR=""
PURGE=0

usage() {
	sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1 ;;
		--ide) ONLY_IDE="${2:-}"; shift ;;
		--skills-dir) SKILLS_DIR="${2:-}"; shift ;;
		--purge) PURGE=1 ;;
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

skills_dir_for() {
	case "$1" in
		claude) printf '%s\n' "$HOME/.claude/skills" ;;
		opencode) printf '%s\n' "$HOME/.config/opencode/skills" ;;
		codex) printf '%s\n' "$HOME/.codex/skills" ;;
		*) return 1 ;;
	esac
}

remove_from() {
	local ide="$1" root dst
	# Install accepts --skills-dir, so removal has to as well; a skill you can
	# put somewhere and not take away is a worse deal than no flag at all.
	if [ -n "$SKILLS_DIR" ]; then
		root="$SKILLS_DIR"
	else
		root="$(skills_dir_for "$ide")"
	fi
	dst="$root/d2-diagram"
	if [ ! -d "$dst" ]; then
		say "[$ide] not installed"
		return 0
	fi
	case "$dst" in
		*/d2-diagram) ;;
		*) echo "refusing to delete $dst — not a d2-diagram directory" >&2; exit 2 ;;
	esac
	say "[$ide] removing $dst"
	run rm -rf "$dst"
	REMOVED=$((REMOVED + 1))
}

if [ -n "$ONLY_IDE" ] && ! skills_dir_for "$ONLY_IDE" >/dev/null 2>&1; then
	echo "unknown assistant: $ONLY_IDE (expected claude, opencode or codex)" >&2
	exit 2
fi

REMOVED=0
if [ -n "$ONLY_IDE" ]; then
	remove_from "$ONLY_IDE"
else
	for ide in claude opencode codex; do
		remove_from "$ide"
	done
fi

if [ "$PURGE" -eq 1 ] && [ -d "$BACKUP_ROOT" ]; then
	case "$BACKUP_ROOT" in
		"$HOME"/*) ;;
		*) echo "refusing to purge $BACKUP_ROOT — outside \$HOME" >&2; exit 2 ;;
	esac
	say "removing backups under $BACKUP_ROOT"
	run rm -rf "$BACKUP_ROOT"
elif [ -d "$BACKUP_ROOT" ]; then
	say "backups kept in $BACKUP_ROOT — pass --purge to delete them"
fi

say ""
if [ "$DRY_RUN" -eq 1 ]; then
	say "dry run — nothing was changed"
else
	say "removed from $REMOVED assistant(s)"
fi
