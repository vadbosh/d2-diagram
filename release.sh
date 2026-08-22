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

# Machine-specific paths belong to the machine, not to a public repository.
# D2_MIRRORS is a colon-separated list of directories holding a COPY of the
# skill that install.sh does not write — a config canon that redistributes it,
# a second checkout, a container image. A copy that is behind is a copy that
# will be read: this repository and one such canon disagreed on the version for
# a day, and nothing noticed.
mirrors() {
	printf '%s\n' "${D2_MIRRORS:-}" | tr ':' '\n' | while read -r d; do
		[ -n "$d" ] && [ -f "$d/SKILL.md" ] && printf '%s\n' "$d"
	done
}

version_of() {
	sed -n 's/^ *version: *"\([^"]*\)".*/\1/p' "$1" | head -1
}

version() {
	version_of "$SKILL"
}

check_mirrors() {
	local v="$1" d behind=0 n=0 mv same f
	while read -r d; do
		[ -n "$d" ] || continue
		n=$((n + 1))
		mv="$(version_of "$d/SKILL.md")"
		same=1
		for f in SKILL.md references/theme.d2 references/example-terraform-layers.d2 \
		         references/example-code-structure.d2 references/example-data-model.d2; do
			cmp -s "$SRC/skill/$f" "$d/$f" || same=0
		done
		if [ "$mv" = "$v" ] && [ "$same" -eq 1 ]; then
			continue
		fi
		[ "$behind" -eq 0 ] && echo "  mirrors behind:"
		behind=$((behind + 1))
		echo "    ${d/#$HOME/\~}  version ${mv:-none}$([ "$same" -eq 0 ] && echo ", content differs")"
	done <<-EOF
	$(mirrors)
	EOF

	if [ "$behind" -gt 0 ]; then
		echo "                     copy skill/ over them, or drop them from D2_MIRRORS"
		return 1
	fi
	# "0 mirrors, all current" reads as a check that passed; nothing was
	# checked. An unset D2_MIRRORS is the normal case on a fresh clone, and
	# saying so is the difference between a fact and a formality.
	if [ "$n" -eq 0 ]; then
		echo "  mirrors:           none configured — set D2_MIRRORS to compare copies"
		return 0
	fi
	echo "  mirrors:           $n, all at $v"
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

	# Commits after the tag are the normal state between releases, not a fault
	# — reported, never counted as a problem. A check that is always red stops
	# being read, which costs more than the thing it was watching for.
	if git -C "$SRC" rev-parse "v$v" >/dev/null 2>&1; then
		local ahead
		ahead="$(git -C "$SRC" rev-list --count "v$v..HEAD")"
		if [ "$ahead" -gt 0 ]; then
			echo "  unreleased:        $ahead commit(s) since v$v — bump the version to release them"
		else
			echo "  unreleased:        nothing since v$v"
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
	done < <(grep -oE '(\./)?(release\.sh|install\.sh|uninstall\.sh|render\.sh|CHANGELOG\.md|CONTRIBUTING\.md|tests/|examples/|lib/)' "$SKILL" | sort -u || true)
	[ "$leak" -eq 0 ] && echo "  shipped content:   no references to files that do not travel with the skill"
	problems=$((problems + leak))

	check_mirrors "$v" || problems=$((problems + 1))

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
