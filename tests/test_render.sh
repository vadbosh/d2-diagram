#!/usr/bin/env bash
# Check that everything the skill ships still compiles, and that the rules the
# skill states about its own output actually hold.
#
#   ./tests/test_render.sh
#
# Requires the d2 binary. Without it the suite skips rather than fails, because
# the repository is still useful to read on a machine that has no d2.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REFS="$SRC/skill/references"
WORK="$(mktemp -d)"
trap '[ -n "${WORK:-}" ] && rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$*"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

# 0. The gallery pictures match the sources they were built from. This one needs
#    neither d2 nor a browser — it compares recorded hashes — so it runs even
#    where nothing can be rendered, which is exactly the case in CI.
if "$SRC/render.sh" --check >/dev/null 2>&1; then
	ok "gallery pictures match their sources"
else
	no "gallery is out of date — run ./render.sh"
	"$SRC/render.sh" --check 2>&1 | sed 's/^/     /'
fi

if ! command -v d2 >/dev/null 2>&1; then
	printf '\nd2 not on PATH — skipping the render suite (%s passed so far)\n' "$PASS"
	[ "$FAIL" -eq 0 ]
	exit
fi

# 1. Every shipped example compiles — both the skill references and the gallery.
#    The exit code is what counts: d2 leaves a partial file behind on failure,
#    so the presence of output proves nothing.
for f in "$REFS"/example-*.d2 "$SRC"/examples/*.d2; do
	[ -e "$f" ] || continue
	name="$(basename "$f")"
	if d2 "$f" "$WORK/$name.svg" >/dev/null 2>&1; then
		ok "compiles: $name"
	else
		no "compiles: $name"
	fi
done

# 1b. Every gallery source has a committed PNG beside it. A source without its
#     picture means the README shows a broken image to everyone.
for f in "$SRC"/examples/*.d2; do
	[ -e "$f" ] || continue
	png="${f%.d2}.png"
	if [ -f "$png" ]; then
		ok "rendered: $(basename "$png")"
	else
		no "rendered: $(basename "$png") is missing — re-render it"
	fi
done

# 2. No example may produce a <foreignObject>. That element is what a markdown
#    label compiles to, and GitHub refuses to render an SVG containing one — the
#    whole reason the skill bans |md blocks.
for f in "$WORK"/*.svg; do
	[ -e "$f" ] || continue
	name="$(basename "$f" .svg)"
	if grep -q '<foreignObject' "$f"; then
		no "no foreignObject: $name"
	else
		ok "no foreignObject: $name"
	fi
done

# 3. The theme is a valid import on its own — a broken theme takes every diagram
#    with it, and the error surfaces far from the cause.
if d2 validate "$REFS/theme.d2" >/dev/null 2>&1; then
	ok "theme.d2 validates"
else
	no "theme.d2 validates"
fi

# 4. The skill claims a class roster; a diagram referring to a class the theme
#    does not define renders silently unstyled, which is worse than an error.
missing=0
for cls in spine zone zone-warm layer focus hot comp store ext dep read cut gone; do
	grep -q "^  $cls: {\|^classes\.$cls: {" "$REFS/theme.d2" || { echo "    class not in theme: $cls"; missing=1; }
done
if [ "$missing" -eq 0 ]; then
	ok "every documented class exists in theme.d2"
else
	no "every documented class exists in theme.d2"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
