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
# whatever rasterizer is at hand.
#
# theme.d2 is hashed into every entry, because changing it changes every picture.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES="$SRC/examples"
THEME="$SRC/skill/references/theme.d2"
MANIFEST="$EXAMPLES/.rendered"
SCALE="${D2_RENDER_SCALE:-2}"

# librsvg ignores the @font-face fonts D2 embeds as data URLs, so left alone it
# falls back to whatever sans it finds and the text stops fitting the boxes D2
# sized for it — measured: "unit_price_cents bigint" ran together under DejaVu.
# What D2 embeds is a subset of Source Sans Pro, renamed per diagram, so the fix
# is to point the four text classes at an installed Source Sans of the same
# metrics. Only the class rules quote the family name; the @font-face blocks do
# not, which is what makes the substitution safe to do with sed.
D2_SANS="${D2_SANS:-Source Sans 3}"
D2_MONO="${D2_MONO:-monospace}"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

sha() { sha256sum "$1" | cut -d' ' -f1; }

# What turns the scratch SVG into a raster. d2 can export PNG itself, but first
# downloads a Playwright driver, and that download is dead on every platform:
# playwright.azureedge.net is retired and its replacement answers a redirect the
# Go client does not follow — see docs/patterns.en.md.
#
# rsvg-convert (librsvg) is preferred. It needs no browser and no driver cache,
# and the SVG's own viewBox sets the canvas, so there is no window to size. A
# headless browser stays as the fallback for a box that has one but no librsvg;
# D2_BROWSER still forces that path.
#
# Prints "<kind> <path>", kind being rsvg or browser.
find_rasterizer() {
	local c
	if [ -n "${D2_BROWSER:-}" ]; then
		printf 'browser %s\n' "$D2_BROWSER"
		return 0
	fi
	if command -v rsvg-convert >/dev/null 2>&1; then
		printf 'rsvg %s\n' "$(command -v rsvg-convert)"
		return 0
	fi
	for c in "$HOME/.cache/ms-playwright/chromium-1228/chrome-linux/chrome" \
	         chromium chromium-browser google-chrome; do
		if [ -x "$c" ]; then printf 'browser %s\n' "$c"; return 0; fi
		if command -v "$c" >/dev/null 2>&1; then printf 'browser %s\n' "$(command -v "$c")"; return 0; fi
	done
	return 1
}

retarget_fonts() {
	sed -E \
		-e "s/font-family: \"d2-[0-9]+-font-regular\"/font-family: \"$D2_SANS\"/" \
		-e "s/font-family: \"d2-[0-9]+-font-bold\"/font-family: \"$D2_SANS\"; font-weight: 700/" \
		-e "s/font-family: \"d2-[0-9]+-font-italic\"/font-family: \"$D2_SANS\"; font-style: italic/" \
		-e "s/font-family: \"d2-[0-9]+-font-mono\"/font-family: \"$D2_MONO\"/" \
		"$1"
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
	local spec kind tool d2 name w h dims
	if ! command -v d2 >/dev/null 2>&1; then
		echo "d2 is not on PATH — cannot render" >&2
		exit 3
	fi
	if ! spec="$(find_rasterizer)"; then
		echo "no rasterizer found; install librsvg2-bin for rsvg-convert, or set D2_BROWSER to a headless browser" >&2
		exit 3
	fi
	kind="${spec%% *}"
	tool="${spec#* }"
	if [ "$kind" = rsvg ] && command -v fc-list >/dev/null 2>&1 &&
		! fc-list : family 2>/dev/null | grep -qiF "$D2_SANS"; then
		echo "the rsvg path needs the \"$D2_SANS\" font — apt install fonts-adobe-sourcesans3" >&2
		echo "without it the labels are measured with the wrong metrics and overflow their boxes" >&2
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
		if [ "$kind" = rsvg ]; then
			retarget_fonts "/tmp/$name.svg" > "/tmp/$name.rsvg.svg"
			"$tool" -z "$SCALE" "/tmp/$name.rsvg.svg" -o "$EXAMPLES/$name.png"
		else
			"$tool" --headless --disable-gpu --no-sandbox --hide-scrollbars \
				--force-device-scale-factor="$SCALE" --window-size="$w,$h" \
				--screenshot="$EXAMPLES/$name.png" "file:///tmp/$name.svg" >/dev/null 2>&1
		fi
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
