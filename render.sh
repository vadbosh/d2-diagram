#!/usr/bin/env bash
# render.sh — rebuild every gallery picture and record what it was built from.
#
#   ./render.sh            re-render examples/*.d2 to PNG and stamp the manifest
#   ./render.sh --check    verify the committed PNGs match the current sources
#
# Why a manifest. The .d2 is the source and the .png is what a reader sees, and
# nothing stops someone editing the first and forgetting the second — the one
# failure this whole approach still allows. examples/.rendered records the
# sha256 of each source and of the picture built from it, so the test suite can
# say which pair has drifted apart. It compares hashes of the *inputs*, not of
# the images: a PNG is not reproducible across machines, since it comes out of
# whatever headless browser is at hand.
#
# theme.d2 is hashed into every entry, because changing it changes every picture.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES="$SRC/examples"
THEME="$SRC/skill/references/theme.d2"
MANIFEST="$EXAMPLES/.rendered"
SCALE="${D2_RENDER_SCALE:-2}"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

sha() { sha256sum "$1" | cut -d' ' -f1; }

# The browser that turns the scratch SVG into a raster. d2 can export PNG itself
# but downloads a Playwright driver to do it, and that download 404s on
# linux/arm64 — see docs/patterns.en.md.
find_browser() {
	local c
	for c in "${D2_BROWSER:-}" \
	         "$HOME/.cache/ms-playwright/chromium-1228/chrome-linux/chrome" \
	         chromium chromium-browser google-chrome; do
		[ -n "$c" ] || continue
		if [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
		if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
	done
	return 1
}

expected_line() {
	local d2="$1" png="${1%.d2}.png"
	printf '%s %s %s %s\n' "$(sha "$d2")" \
		"$([ -f "$png" ] && sha "$png" || echo missing)" \
		"$(sha "$THEME")" "$(basename "$d2")"
}

check() {
	local d2 name stale=0
	if [ ! -f "$MANIFEST" ]; then
		echo "no $MANIFEST — run ./render.sh to create it" >&2
		return 3
	fi
	for d2 in "$EXAMPLES"/*.d2; do
		[ -e "$d2" ] || continue
		name="$(basename "$d2")"
		if ! grep -qxF "$(expected_line "$d2")" "$MANIFEST"; then
			[ "$stale" -eq 0 ] && echo "  out of date — the source changed after the picture was made:"
			stale=$((stale + 1))
			echo "    $name"
		fi
	done
	if [ "$stale" -gt 0 ]; then
		echo "  run ./render.sh and commit both the .png and examples/.rendered"
		return 3
	fi
	echo "  gallery: every picture matches its source"
}

render() {
	local browser d2 name w h dims
	if ! command -v d2 >/dev/null 2>&1; then
		echo "d2 is not on PATH — cannot render" >&2
		exit 3
	fi
	if ! browser="$(find_browser)"; then
		echo "no headless browser found; set D2_BROWSER to one" >&2
		exit 3
	fi

	: > "$MANIFEST.tmp"
	for d2 in "$EXAMPLES"/*.d2; do
		[ -e "$d2" ] || continue
		name="$(basename "$d2" .d2)"
		d2 fmt "$d2" >/dev/null
		if ! d2 "$d2" "/tmp/$name.svg" >/dev/null 2>&1; then
			echo "FAILED to compile $name.d2" >&2
			rm -f "$MANIFEST.tmp"
			exit 3
		fi
		dims="$(sed -n 's/.*viewBox="0 0 \([0-9]*\) \([0-9]*\)".*/\1 \2/p' "/tmp/$name.svg" | head -1)"
		w="${dims% *}"; h="${dims#* }"
		"$browser" --headless --disable-gpu --no-sandbox --hide-scrollbars \
			--force-device-scale-factor="$SCALE" --window-size="$w,$h" \
			--screenshot="$EXAMPLES/$name.png" "file:///tmp/$name.svg" >/dev/null 2>&1
		printf '%-28s %sx%s  ratio %s\n' "$name" "$w" "$h" \
			"$(awk -v a="$w" -v b="$h" 'BEGIN{printf "%.2f", a/b}')"
		expected_line "$d2" >> "$MANIFEST.tmp"
	done
	mv "$MANIFEST.tmp" "$MANIFEST"
	echo "stamped $MANIFEST"
}

if [ "$CHECK_ONLY" -eq 1 ]; then
	check
else
	render
fi
