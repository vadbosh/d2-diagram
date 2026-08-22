#!/usr/bin/env python3
"""Find edges drawn through a label, in a D2-generated SVG.

The one defect this repository keeps producing is invisible to `d2 validate`,
because it is not in the source: D2 centres a container's title on its top
border, and `dagre` routes an incoming edge into the top of that same
container. The two collide and the arrow is drawn straight through the text.
Two of the four gallery diagrams shipped that way — in one the arrow replaced
the em-dash in "Kubernetes — namespace gateway-system" and read as punctuation.

Reading the picture catches it, but only if you crop and look at 1:1; at
full-page scale a 2 px line across a label is invisible. This is the mechanical
version of that look.

    check_labels.py FILE.svg [more.svg ...]

Exit 0 when nothing crosses, 1 when something does, 2 on a usage error. Every
finding prints the label, the offending edge, and the `magick` crop that shows
it, so the report ends where a human can confirm it.

Widths come from the real font when fontTools is importable, and from an
average-advance estimate when it is not — the estimate is deliberately narrow,
so a missing dependency loses findings rather than inventing them. `render.sh`
runs this under `uv run --with fonttools` so the exact path is the normal one
without anything being installed system-wide.
"""

from __future__ import annotations

import base64
import binascii
import html
import re
import sys
from pathlib import Path

# D2 writes one class per font style and nothing else; the family is its own
# embedded subset, which is Source Sans Pro. Source Sans 3 is its successor and
# what `render.sh` repoints the SVG at, so measuring with 3 measures what the
# PNG will actually be drawn with.
FONT_DIRS = [
    "/usr/share/fonts/opentype/sourcesans3",
    "/usr/share/fonts/truetype/sourcesans3",
]
FONT_FILES = {
    "text-bold": "SourceSans3-Bold.otf",
    "text-italic": "SourceSans3-It.otf",
    "": "SourceSans3-Regular.otf",
}

# Fallback when no font is readable: mean advance of Source Sans 3 Bold over
# ASCII, in em units. Under-measuring is the safe direction here.
MEAN_ADVANCE_EM = 0.48

# A baseline is not the top of the text. Cap height and descender, in em.
ASCENT_EM = 0.75
DESCENT_EM = 0.25


def _font_path(cls: str) -> str | None:
    name = FONT_FILES.get(cls, FONT_FILES[""])
    for d in FONT_DIRS:
        p = Path(d) / name
        if p.exists():
            return str(p)
    return None


class Measurer:
    """Text width in px, exact where the font can be read."""

    def __init__(self) -> None:
        self.exact = False
        self._fonts: dict[str, object] = {}
        try:
            from fontTools.ttLib import TTFont  # noqa: F401
            self.exact = True
        except ImportError:
            pass

    def _font(self, cls: str):
        if cls in self._fonts:
            return self._fonts[cls]
        font = None
        path = _font_path(cls)
        if path:
            try:
                from fontTools.ttLib import TTFont
                font = TTFont(path, lazy=True)
            except Exception:
                font = None
        self._fonts[cls] = font
        return font

    def width(self, text: str, size: float, cls: str) -> float:
        font = self._font(cls) if self.exact else None
        if font is None:
            return len(text) * size * MEAN_ADVANCE_EM
        try:
            cmap = font.getBestCmap()
            hmtx = font["hmtx"]
            upem = font["head"].unitsPerEm
            total = 0
            for ch in text:
                glyph = cmap.get(ord(ch))
                if glyph is None:
                    total += upem * MEAN_ADVANCE_EM
                    continue
                total += hmtx[glyph][0]
            return total * size / upem
        except Exception:
            return len(text) * size * MEAN_ADVANCE_EM


def _decode_id(cls_attr: str) -> str:
    """D2 puts base64 of the element id in the group's class attribute.

    An edge's id contains an arrow, which is how an edge is told from a node
    without guessing from geometry.
    """
    for token in cls_attr.split():
        try:
            raw = base64.b64decode(token + "=" * (-len(token) % 4), validate=True)
        except (binascii.Error, ValueError):
            continue
        try:
            # The id travels HTML-escaped inside the base64, so an edge arrow
            # arrives as `-&gt;` and never matches a literal `->`. That single
            # missing unescape made every edge look like a node, which made the
            # checker find nothing and report success.
            return html.unescape(raw.decode("utf-8"))
        except UnicodeDecodeError:
            continue
    return ""


def _is_edge(element_id: str) -> bool:
    return "->" in element_id or "--" in element_id


SVG_NS = "{http://www.w3.org/2000/svg}"
NUM_RE = re.compile(r'-?\d+(?:\.\d+)?')


def _style(blob: str) -> dict:
    out = {}
    for part in blob.split(";"):
        if ":" in part:
            k, _, v = part.partition(":")
            out[k.strip()] = v.strip()
    return out


def _points(d: str) -> list[tuple[float, float]]:
    """Every coordinate pair in a path, on-curve or not.

    Treating control points as vertices makes the polyline a little wider than
    the curve it describes. For a proximity test that is the right error: it
    reports a near miss rather than missing a hit.
    """
    nums = [float(n) for n in NUM_RE.findall(d)]
    return list(zip(nums[0::2], nums[1::2]))


def _segments_cross_box(pts, box) -> bool:
    x0, y0, x1, y1 = box
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        # Cheap reject: the segment's own bounding box misses the label's.
        if max(ax, bx) < x0 or min(ax, bx) > x1:
            continue
        if max(ay, by) < y0 or min(ay, by) > y1:
            continue
        # Sample the segment. The boxes are tens of pixels; a 40-step walk
        # cannot step over one.
        for i in range(41):
            t = i / 40
            px, py = ax + (bx - ax) * t, ay + (by - ay) * t
            if x0 <= px <= x1 and y0 <= py <= y1:
                return True
    return False


def _owner(elem, parents) -> str:
    """The id of the nearest enclosing element group.

    Walked rather than pattern-matched: a container <g> holds the <g> of every
    node inside it, and a regex with a non-greedy `</g>` stops at the first
    closing tag it meets. That read 9 of 22 labels and none of the edge paths —
    a checker that found nothing and reported success.
    """
    node = parents.get(elem)
    while node is not None:
        eid = _decode_id(node.get("class", ""))
        if eid:
            return eid
        node = parents.get(node)
    return ""


def check(path: Path, measurer: Measurer) -> list[str]:
    import xml.etree.ElementTree as ET

    root = ET.fromstring(path.read_text(encoding="utf-8"))
    parents = {child: parent for parent in root.iter() for child in parent}

    # The inner <svg> carries a viewBox whose origin is negative, so a
    # coordinate in the file is not a pixel in the PNG. Without this the crop
    # hint points at a different part of the picture, which is worse than no
    # hint — it shows something innocent and reads as a false positive.
    off_x = off_y = 0.0
    for elem in root.iter():
        if elem.tag.replace(SVG_NS, "") == "svg" and elem is not root:
            vb = (elem.get("viewBox") or "").split()
            if len(vb) == 4:
                off_x, off_y = float(vb[0]), float(vb[1])
            break

    labels, edges = [], []

    for elem in root.iter():
        tag = elem.tag.replace(SVG_NS, "")
        owner = _owner(elem, parents)

        if tag == "path" and _is_edge(owner):
            pts = _points(elem.get("d", ""))
            if len(pts) > 1:
                edges.append((owner, pts))
            continue

        if tag != "text" or _is_edge(owner):
            # An edge's own label sits on its own line by design; only a
            # foreign edge crossing a label is a defect.
            continue

        text = "".join(elem.itertext()).strip()
        if not text:
            continue
        try:
            x, y = float(elem.get("x")), float(elem.get("y"))
        except (TypeError, ValueError):
            continue
        st = _style(elem.get("style", ""))
        size = float(st.get("font-size", "16px").rstrip("px"))
        cls_attr = elem.get("class", "")
        cls = "text-bold" if "text-bold" in cls_attr else \
              "text-italic" if "text-italic" in cls_attr else ""
        w = measurer.width(text, size, cls)
        anchor = st.get("text-anchor", "start")
        x0 = x - w / 2 if anchor == "middle" else x - w if anchor == "end" else x
        labels.append((text, (x0, y - size * ASCENT_EM, x0 + w, y + size * DESCENT_EM)))

    findings = []
    for text, box in labels:
        for edge_id, pts in edges:
            if _segments_cross_box(pts, box):
                x0, y0, x1, y1 = box
                x0, x1 = x0 - off_x, x1 - off_x
                y0, y1 = y0 - off_y, y1 - off_y
                pad = 40
                findings.append(
                    f"{path.name}: edge {edge_id} crosses the label {text!r}\n"
                    f"    look: magick {path.with_suffix('.png').name} -crop "
                    f"{int((x1 - x0) + pad * 2) * 2}x{int((y1 - y0) + pad * 2) * 2}"
                    f"+{int(x0 - pad) * 2}+{int(y0 - pad) * 2} +repage /tmp/check.png"
                )
                break

    return findings


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2

    measurer = Measurer()
    if not measurer.exact:
        print("note: fontTools not importable — widths are estimated, "
              "so a narrow collision can be missed", file=sys.stderr)

    findings = []
    for name in argv:
        p = Path(name)
        if not p.exists():
            print(f"no such file: {p}", file=sys.stderr)
            return 2
        findings += check(p, measurer)

    for f in findings:
        print(f)
    if findings:
        print(f"\n{len(findings)} label(s) crossed by an edge")
        return 1
    print(f"labels: nothing crossed in {len(argv)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
