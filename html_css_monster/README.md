# OCaml HTML × CSS monster

A standalone OCaml tool with **112 HTML element constructors**, **176 CSS
property constructors**, a CSS-value ADT, HTML attributes/nodes, and stylesheet
ADTs for selectors, pseudo-classes/elements, media queries and feature queries.
Nine additional rule features bring the random feature pool to **185**.

The requested “90% of the most common” is implemented as a broad, explicit
common-authoring catalog. No frequency dataset is supplied, so this is not a
measured claim of 90% web usage or 90% of the entire HTML/CSS specifications.
The exact catalog and its usage counts are in the generated JSON manifest.
Obsolete HTML elements and arbitrary custom elements are excluded. Foreign
SVG is used as an embedded image, not counted as HTML element coverage.

## Build and generate

Requires only `ocamlc` and Make; no opam packages, dune, network or service.

```sh
make -C html_css_monster generate
```

This creates [monster.html](monster.html), a roughly 2.7 MB page with **512
stress boxes across 24 increasing difficulty levels**, plus
[monster.html.json](monster.html.json), its full reproducibility/coverage manifest.
Open the HTML file directly in a browser. All assets use data URLs; the only
script element holds inert JSON. Forms, disclosures and controls use native
browser behavior. No JavaScript or external stylesheet/font/media is fetched.

```sh
html_css_monster/monster --boxes 2000 --levels 32 --seed 42 --out /tmp/monster.html
html_css_monster/monster --boxes 32 --levels 8 --seed 123 --out /tmp/small.html
```

`--manifest PATH` overrides the default `OUT.json`. Box counts range from 1 to
10,000; levels range from 1 to 256 and are capped at the number of boxes.
The same arguments and OCaml random implementation produce identical bytes.

## How the random subsets grow

For each level, the generator computes a feature quota increasing from **1 to
185**. Every box gets an independently shuffled subset of exactly that size,
with no duplicates; declaration values are then sampled from typed candidates.
Subsets are not required to contain the preceding box's subset. **Their sizes
are monotone; their identities vary.** Every box in the final level uses the
entire feature pool. A single-level run uses the full pool immediately.

The generated surfaces combine layout, sizing, logical properties, margins,
padding, borders, backgrounds, typography, RTL/vertical writing, flex/grid,
floats, positioning, scrolling, columns, tables, transforms, clipping, filters,
animations, containment, form styling, counters and custom properties. Rule
features add hover/focus states, `::before`, `:nth-child`, responsive media,
color/motion preference queries, `@supports`, and child selectors.

Labels and feature lists live outside each randomized surface. Each specimen
has a bounded, scrollable viewport, so contradictory combinations can overflow,
clip or rearrange the sample without losing the specimen's identity. Animations
honor reduced-motion preferences. CSS combinations are intentionally strange;
not every property applies to every selected element or display mode.

An independent element atlas guarantees that all 112 supported tags occur in
the document, even for a one-box run. Context-sensitive elements have complete
fixtures: table sections/cells, lists, options, ruby annotations, fieldset/legend,
details/summary, figure/caption, image maps and media. Document-only elements live
in the scaffold/head. `template`, `noscript`, fallback content and slots retain
their native conditional/inert semantics; occurrence is not a claim that all
elements are simultaneously visible or all APIs are implemented.

## Source and checks

All implementation code and catalogs are in [monster.ml](monster.ml).
`Html.tag`, `Html.attribute`, `Html.node`, `Css.property`, `Css.value`,
`Stylesheet.selector`, `Stylesheet.rule`, and `feature` are ADTs.
Tag/property catalogs contain named constructors rather than arbitrary tag or
property strings. CSS keyword and identifier values are validated tokens.

HTML text/attributes and CSS strings are escaped separately. Void elements
reject children. Raw-text style/script nodes reject closing-tag injection.
The renderer does not enforce the complete HTML content model; the generated
fixtures supply the relevant contexts.

```sh
make -C html_css_monster test
```

The OCaml self-checks exercise catalog uniqueness, escaping and rejection paths.
Python standard-library tests execute the OCaml program and check deterministic
seeds, monotone subset sizes, duplicate-free selections, source/manifest agreement,
all-tag/all-feature coverage, tag balancing, contextual parents, unique IDs,
local references, offline resources, and CLI boundaries. These checks are not
a browser compatibility or full standards-conformance suite.
