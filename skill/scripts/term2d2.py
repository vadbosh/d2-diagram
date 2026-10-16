#!/usr/bin/env python3
"""Terminal output on stdin -> a D2 grid that looks like a dark terminal.

    script -qc "stty cols 120; mytool list" /dev/null | tr -d '\\r' \\
        | python3 term2d2.py 'mytool list' > docs/list.d2

The first argument is the command shown on the prompt line. ANSI colour (SGR
30-37, 90-97, bold) is kept; every other escape is dropped. --dim PREFIX greys
out the lines that start with PREFIX — legends, footers; give it more than once.

One grid row per line. A row is cut into cells at every run of two or more
spaces and at every colour change, and a cell never starts with a space: SVG
collapses repeated spaces, and D2 trims a label, so the columns would drift.
Every cell is exactly as wide as its characters, which is what keeps a table
in a monospace font lined up."""
import argparse
import re
import sys

BG, INK, DIM = "#1f2430", "#d8dee9", "#8b93a3"
# A dark-terminal palette for SGR 30-37 and their bright 90-97 forms.
PALETTE = {30: "#3b4252", 31: "#ef7a7a", 32: "#9ccc65", 33: "#e0a75e",
           34: "#81a1c1", 35: "#b48ead", 36: "#88c0d0", 37: INK,
           90: DIM, 91: "#ff8f8f", 92: "#b5e48c", 93: "#ffd75f",
           94: "#9ab8e0", 95: "#d0a4e0", 96: "#a3e4f0", 97: "#ffffff"}
SGR = re.compile(r'\x1b\[([0-9;]*)m')
OTHER = re.compile(r'\x1b\[[0-9;?]*[A-Za-ln-z]|\x1b\][^\x07]*\x07')

ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
ap.add_argument('command', help='the command shown on the prompt line')
ap.add_argument('--dim', action='append', default=[], metavar='PREFIX',
                help='grey out lines that start with PREFIX')
ap.add_argument('--font-size', type=int, default=13)
ap.add_argument('--char-width', type=float,
                help='px per character (default: 0.6077 x font size — DejaVu Sans Mono, 7.9 at 13 px)')
args = ap.parse_args()
if args.char_width is None:
    args.char_width = round(args.font_size * 0.6077, 2)
ROW = round(args.font_size * 1.55)


def q(s):
    # Single quotes: `$` in a double-quoted D2 label starts a substitution.
    return "'" + s.replace("'", "’") + "'"


def segments(line):
    out, colour, bold, pos = [], INK, False, 0
    for m in SGR.finditer(line):
        if m.start() > pos:
            out.append((line[pos:m.start()], colour, bold))
        for code in (int(c) for c in (m.group(1) or '0').split(';') if c.isdigit()):
            if code == 0:
                colour, bold = INK, False
            elif code == 1:
                bold = True
            elif code == 22:
                bold = False
            elif code == 39:
                colour = INK
            elif code in PALETTE:
                colour = PALETTE[code]
        pos = m.end()
    if pos < len(line):
        out.append((line[pos:], colour, bold))
    return out


def cells(line, dim):
    res = []
    for text, colour, bold in segments(line):
        for piece in re.split(r'(?<=  )(?=\S)', text):
            if piece:
                res.append([piece, DIM if dim else colour, bold])
    # Leading spaces move to the end of the cell before, and a cell of spaces
    # only joins it whole: a trailing space is invisible, a leading one is not.
    out = []
    for piece in res:
        lead = len(piece[0]) - len(piece[0].lstrip(' '))
        if out and lead:
            out[-1][0] += ' ' * lead
            piece[0] = piece[0][lead:]
        if piece[0]:
            out.append(piece)
    return out


def cell(name, text, colour, bold):
    return (f"    {name}: {q(text.rstrip() or ' ')} {{\n"
            f"      width: {max(1, round(args.char_width * len(text)))}\n"
            f"      height: {ROW}\n      label.near: center-left\n"
            f"      style: {{fill: transparent; stroke-width: 0; font: mono; "
            f"font-size: {args.font_size}; font-color: \"{colour}\"; "
            f"bold: {'true' if bold else 'false'}}}\n    }}\n")


text = OTHER.sub('', sys.stdin.read().replace('\r', '')).expandtabs()
lines = text.split('\n')
while lines and not lines[-1].strip():
    lines.pop()

BLANK = [[" ", INK, False]]
rows = [[["$ " + args.command, INK, True]], BLANK]
for l in lines:
    rows.append(cells(l, any(l.startswith(p) for p in args.dim)) or BLANK)
pad = ["  ", INK, False]                 # two characters of margin each side
rows = [BLANK] + [[list(pad)] + r + [list(pad)] for r in rows] + [BLANK]

out = ["direction: down\n", "vars: {d2-config: {pad: 0}}\n",
       f"term: \"\" {{\n  grid-columns: 1\n  grid-gap: 0\n"
       f"  style: {{fill: \"{BG}\"; stroke: \"{BG}\"; border-radius: 8}}\n"]
for r, row in enumerate(rows):
    out.append(f"  l{r}: \"\" {{\n    grid-rows: 1\n    grid-columns: {len(row)}\n"
               f"    grid-gap: 0\n    style: {{fill: transparent; stroke-width: 0}}\n")
    out.extend(cell(f"c{c}", t, colour, bold) for c, (t, colour, bold) in enumerate(row))
    out.append("  }\n")
out.append("}\n")
sys.stdout.write("".join(out))
