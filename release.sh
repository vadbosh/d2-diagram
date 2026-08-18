#!/usr/bin/env bash
# release.sh — keep the version, the changelog and the tag saying the same thing.
#
#   ./release.sh check     verify they agree; exit 3 if they do not
#   ./release.sh tag       create the missing tag for the current version
#
# Three places record a release and each drifts on its own: `version:` inside
# skill/SKILL.md is what ships, CHANGELOG.md is what a reader looks at, a git tag
# is what `git checkout` needs. A release where the three disagree is worse than
# an untagged one — the disagreement is silent, and each source looks
# authoritative. This repository shipped with 1.0 in the skill and 0.1.0 in the
# changelog, which is exactly the failure this script exists to catch.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SRC/skill/SKILL.md"
LOG="$SRC/CHANGELOG.md"

version() {
	sed -n 's/^ *version: *"\([^"]*\)".*/\1/p' "$SKILL" | head -1
}

check() {
	local v problems=0
	v="$(version)"
	if [ -z "$v" ]; then
		echo "no version: field in ${SKILL#"$SRC"/}" >&2
		return 3
	fi
	echo "  skill version:     $v"

	if grep -q "^## $v\( \|$\)" "$LOG"; then
		echo "  changelog:         has a section for $v"
	else
		echo "  changelog:         NO section '## $v' in CHANGELOG.md"
		problems=$((problems + 1))
	fi

	if git -C "$SRC" rev-parse "v$v" >/dev/null 2>&1; then
		echo "  git tag:           v$v exists"
	else
		echo "  git tag:           v$v is missing — ./release.sh tag creates it"
		problems=$((problems + 1))
	fi

	# A tag that points somewhere other than the current commit means the tag
	# was made, then work continued without a version bump. Both look fine on
	# their own; only the comparison shows it.
	if git -C "$SRC" rev-parse "v$v" >/dev/null 2>&1; then
		local tagged head
		tagged="$(git -C "$SRC" rev-list -n1 "v$v")"
		head="$(git -C "$SRC" rev-parse HEAD)"
		if [ "$tagged" != "$head" ]; then
			echo "  position:          v$v points at ${tagged:0:7}, HEAD is ${head:0:7}"
			echo "                     bump the version, or move the tag deliberately"
			problems=$((problems + 1))
		fi
	fi

	# What ships is read by people who have the skill and nothing else of ours.
	# A path into this checkout, or a file that exists here but is never
	# installed, is unusable for them.
	local leak=0 tok
	while read -r tok; do
		[ -n "$tok" ] || continue
		echo "  shipped leak:      SKILL.md mentions $tok — exists here, never installed"
		leak=1
	done < <(grep -oE '(\./)?(release\.sh|install\.sh|uninstall\.sh|CHANGELOG\.md|CONTRIBUTING\.md|tests/)' "$SKILL" | sort -u || true)
	[ "$leak" -eq 0 ] && echo "  shipped content:   no references to files that do not travel with the skill"
	problems=$((problems + leak))

	if [ "$problems" -eq 0 ]; then
		echo "  everything agrees on $v"
		return 0
	fi
	return 3
}

make_tag() {
	local v
	v="$(version)"
	[ -n "$v" ] || { echo "no version: field in ${SKILL#"$SRC"/}" >&2; exit 3; }

	if ! grep -q "^## $v\( \|$\)" "$LOG"; then
		echo "CHANGELOG.md has no section for $v — write it before tagging" >&2
		exit 3
	fi
	if git -C "$SRC" rev-parse "v$v" >/dev/null 2>&1; then
		echo "v$v already exists" >&2
		exit 3
	fi
	if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
		echo "working tree is dirty — commit first, so the tag points at something real" >&2
		exit 3
	fi

	git -C "$SRC" tag -a "v$v" -m "v$v"
	echo "created v$v at $(git -C "$SRC" rev-parse --short HEAD)"
	echo "push it with:  git push origin v$v"
}

case "${1:-check}" in
	check) check ;;
	tag) make_tag ;;
	-h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
	*) echo "usage: $0 [check|tag]" >&2; exit 2 ;;
esac
