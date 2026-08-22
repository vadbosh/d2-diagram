# Design

Why the tool is D2, why the committed picture is a PNG, and where the whole
approach stops working. Every decision here was made against a real failure, and
the failure is named.

## Why not Mermaid

Mermaid renders natively inside GitHub and GitLab, needs no binary, and for a
five-node flowchart it is the right answer. Two things push a diagram past it:

- **Looks.** Mermaid 11 can do a lot more than it used to — `layout: elk`,
  `look: handDrawn`, full `themeVariables` — but a bundled renderer decides what
  you get. GitLab currently ships mermaid 11.13, where `look` accepts only
  `classic` and `handDrawn`; a diagram written against a newer `look` silently
  renders as the old one. You are styling something you do not control.
- **Layout.** Anything with containers, cross-links and more than a dozen nodes
  ends up fighting the renderer.

The rule of thumb: Mermaid when the renderer is not yours and the diagram is
small. D2 when the diagram is a maintained artefact.

## Why not hand-written SVG

There is a whole class of tools where a model writes the SVG directly. They can
do things D2 cannot — pyramids, Venns, editorial figures — and they look better
in a deck. The cost is that the artefact and the source are the same file: five
hundred lines of coordinates. Nobody reviews that in a pull request, and nobody
edits it a month later; they redraw it.

D2 splits the two. The forty-line source is what a human reads and changes; the
picture is generated.

There is also a running cost. A skill of that kind loads tens of kilobytes of
instructions and then produces hundreds of lines of SVG. This one loads a few
kilobytes and produces forty lines of D2 — roughly an order of magnitude less
per diagram, which matters when diagrams are routine rather than occasional.

## Why PNG is what gets committed

This is the counter-intuitive one. SVG is the better format: vector, small,
self-contained. It is still the wrong thing to commit, for one specific reason.

**GitHub refuses to display an SVG file page.** Embedded in a README the picture
appears, but a click on it lands on a page that says "Unable to render code
block" — on both the Code and the Preview tab. The reader gets a thumbnail
scaled into the README column and no way to enlarge it, which for anything
denser than five boxes means the diagram is decorative.

So the committed artefact is a PNG, embedded wrapped in a link to itself:

```markdown
[![Cluster A](docs/diagrams/cluster-a.png)](docs/diagrams/cluster-a.png)
```

The click then opens GitHub's image viewer at full resolution. The PNG is
rendered at 2× so that view is sharp.

SVG survives only as an intermediate: `d2` renders one, `rsvg-convert`
rasterizes it, the PNG is kept and the SVG is dropped in `/tmp`. Where `d2
x.d2 x.png` works directly there is no SVG at all.

A second reason not to commit it: two rendered files claiming to be the same
diagram will drift the first time someone re-renders only one of them.

## Why the palette lives in one file

`theme.d2` defines the style classes, every diagram imports it with `...@theme`.
This is not tidiness — it is the difference between restyling a repository and
restyling one diagram. The roster is deliberately small and semantic rather than
visual: `spine` for the one or two nodes read first, `focus`/`hot` for what is
currently changing, `ext` for what is outside your control, `dep`/`read`/`cut`
for the kinds of edge. A diagram written in those terms stays readable when the
palette changes underneath it.

## Aspect ratio is a correctness property

A README column is roughly 900 px. A 2:1 canvas therefore renders 20 px type at
about 7 px, and a 4.6:1 canvas is a decorative strip. This is not a styling
detail to fix later — an unreadable thumbnail is a broken diagram.

The fix is usually one word. Changing `direction: right` to `direction: down`
turned a 3521×770 monitoring diagram into 1128×2060: same content, same source,
readable inline. Check the `viewBox` after rendering, not the picture in your
head.

## A defect that exists only in the output

The layout engine decides where everything goes. That is the point of D2, and it
is also why a whole class of defect cannot be seen in the `.d2` at all: the
source is correct, the picture is not, and `d2 validate` has nothing to object
to.

The one that keeps happening: D2 centres a container's title on its top border,
and the engine routes an incoming edge into the top of that same container. The
arrow is drawn through the text. In one diagram here it replaced the em-dash in
`Kubernetes — namespace gateway-system` and read as punctuation.

Choosing the other engine does not help — measured on 0.7.1 against a diagram
built to collide, `dagre` and `elk` both draw through the title. What does help
is a title that leaves the middle of the container free, since the middle is
where the edge comes in: shorten it, move it with `label.near: top-left`, or
both.

Looking at the picture does not catch it. Four diagrams in this gallery were
read at full size by someone who had just spent an hour on this exact defect;
two of the four were called clean and both were crossed. At that scale a 2 px
line across a label is invisible.

So it is checked arithmetically instead. `scripts/check_labels.py` walks the
SVG, measures every node and container label with the font the picture will
actually be drawn in, and reports any edge path that passes through one. It
lives inside `skill/` rather than beside `render.sh`, because only the skill
directory reaches an assistant — a check kept in the repository would be a check
the agent drawing your diagram does not have.

**It reads geometry and nothing else.** A diagram can pass it and still draw a
dependency that does not exist, or leave out the one that matters. That is what
reading the real source before drawing is for, and it is the one part of this
that no tool verifies.

## Where this stops working

D2 places nodes with a layout engine. **Anything whose meaning lives in a
coordinate or an area is out of reach**, and no styling gets around it.

| Works natively | Possible with a grid | Not possible |
|---|---|---|
| architecture, flow, sequence, state, class, ER | quadrant, 2×2 matrix | Venn — circles cannot overlap |
| tree, org chart, nested containers, layers | comparison matrix | radar / spider |
| swimlane, process, data flow, request path | | pyramid, funnel — there is no triangle shape |
| cycles and feedback loops | | bar, line, scatter, gantt — no axes, no chart primitives |
| | | treemap — areas cannot be proportional |

`shape: triangle` is rejected outright: `invalid shape, can only set "triangle"
for arrowheads`.

For the right-hand column use something built for it — a skill that writes SVG
by hand for editorial figures, or a charting library for anything that is
genuinely a chart over data. Bending D2 into a funnel wastes an hour and
produces something worse than either.
