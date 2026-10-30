### 1. Core Data Structures in Blink List Markers

In Chromium’s Blink rendering engine (specifically under the LayoutNG architecture), list markers are decoupled from the legacy `LayoutListMarker` hierarchy and represented as specialized layout nodes managed by the `ListMarker` utility controller.

#### `ListMarker` (`third_party/blink/renderer/core/layout/list_marker.h`)
In LayoutNG, a list marker is not a standalone `LayoutListMarker` subclass if it is text or symbol-based; instead, it is a pseudo-element (`::marker`) whose layout object is either `LayoutNGOutsideListMarker` or `LayoutNGInsideListMarker` (inheriting from `LayoutBlockFlow` or `LayoutInline`), coordinated by the `ListMarker` helper class. `ListMarker` encapsulates state resolution, counter value caching, and intrinsic sizing delegations.

```cpp
// Conceptual representation of Blink's ListMarker state controller
class CORE_EXPORT ListMarker {
  DISALLOW_NEW();
 public:
  enum class ListStyleCategory { kNone, kSymbol, kLanguage, kStaticString };
  enum class MarkerTextFormat { kWithSuffix, kWithoutSuffix };

  // Maps layout object to its marker controller
  static const ListMarker* Get(const LayoutObject* marker);
  
  void UpdateMarkerTextIfNeeded(LayoutObject& marker);
  LayoutObject* MarkerTextLayoutObject(const LayoutObject& marker) const;
  
  // Computes the margins for 'outside' and 'inside' markers based on font metrics
  static std::pair<LayoutUnit, LayoutUnit> InlineMarginsForInside(
      Document&, const ComputedStyleBuilder&, const ComputedStyle& list_item_style);
  static std::pair<LayoutUnit, LayoutUnit> InlineMarginsForOutside(
      Document&, const ComputedStyle& marker_style, const ComputedStyle& list_item_style,
      LayoutUnit marker_inline_size);
};
```

#### `LayoutListMarker` & LayoutNG Equivalents
In the legacy architecture, `LayoutListMarker` inherited directly from `LayoutBox`. Under LayoutNG:
* `LayoutNGOutsideListMarker` inherits from `LayoutBlockFlow`. It generates an out-of-flow-like fragment positioned relative to the parent `LayoutNGListItem` without affecting the inline formatting context's line-breaking width directly.
* `LayoutNGInsideListMarker` inherits from `LayoutInline`. It participates directly in the parent's `NGInlineNode` formatting context as the initial inline item.
* `LayoutListMarkerImage` inherits from `LayoutImage`. When `list-style-image` is valid, the marker's child or the marker itself is replaced by an image layout object.

#### `ListItemType` and `MarkerType`
Blink classifies markers into three core structural archetypes determined by `ComputedStyle` properties (`list-style-type`, `list-style-image`, and `content`):

1. **`kSymbol`**: Geometric glyphs (`disc`, `circle`, `square`, `disclosure-open`, `disclosure-closed`). Historically drawn via direct `GraphicsContext` path primitives (`DrawEllipse`, `FillRect`), LayoutNG increasingly unifies these as text fragments using system fallback glyphs, though custom sizing margins still branch on `ListStyleCategory::kSymbol`.
2. **`kLanguage` (Number/Ordinal)**: Counter-driven strings (`decimal`, `lower-roman`, `cjk-ideographic`, or custom `@counter-style` descriptors). Contains a dynamically resolved `LayoutTextFragment` child holding the evaluated string + suffix.
3. **`kStaticString`**: Arbitrary string literals defined via `list-style-type: "<string>"` or `::marker { content: "..." }`.
4. **`Image`**: Resolved via `StyleImage` (`list-style-image`). Instantiates `LayoutListMarkerImage`, bypassing text metrics entirely in favor of intrinsic image sizing (`ConcreteObjectSize`) and baseline alignment at the bottom of the image box.

---

### 2. Layout Mechanics: `inside` vs. `outside`

W3C CSS Lists and Counters Module Level 3 (§ 3.1 `list-style-position`) defines two placement modes. Blink implements these via distinct layout algorithms in `NGBlockLayoutAlgorithm` and `NGInlineLayoutAlgorithm`.

```
                  list-style-position: outside
+--------------------------------------------------------------+
| List Item Box (LayoutNGListItem)                             |
|                                                              |
|  |<-- Margin Offset -->|                                     |
|  +------------+        +-----------------------------------+ |
|  | ::marker   |        | First Line Box                    | |
|  | [ 1. ]     |        | [ Inline Content...             ] | |
|  +------------+        +-----------------------------------+ |
|  ^                     ^                                     |
|  x_marker              x_content (0 in local coordinates)    |
+--------------------------------------------------------------+

                  list-style-position: inside
+--------------------------------------------------------------+
| List Item Box (LayoutNGListItem)                             |
|                                                              |
|  +---------------------------------------------------------+ |
|  | First Line Box                                          | |
|  | +------------+ +--------------------------------------+ | |
|  | | ::marker   | | Inline Content...                    | | |
|  | | [ 1. ]     | |                                      | | |
|  | +------------+ +--------------------------------------+ | |
|  +---------------------------------------------------------+ |
+--------------------------------------------------------------+
```

#### `list-style-position: inside`
1. **DOM/Layout Tree Attachment**: The marker is instantiated as a `LayoutNGInsideListMarker` (an inline-level box). It is inserted as the first child of the `LayoutNGListItem` (or nested inside the first anonymous block flow if the list item has mixed block/inline children).
2. **Inline Formatting Context (IFC)**: During `NGInlineNode::CollectInlines`, the marker is serialized into the `NGInlineItem` list as `kOpenTag`, followed by its text/image content, and `kCloseTag`.
3. **Line Box Participation**: `NGLineBreaker` treats the marker identically to a `<span>` at the start of the line. Its inline size ($w_{\text{marker}}$) and inline margins ($\text{margin}_{\text{start}}, \text{margin}_{\text{end}}$) consume available line width. Text wraps *underneath* the marker on subsequent lines.

#### `list-style-position: outside`
1. **Layout Tree Attachment**: The marker is instantiated as a `LayoutNGOutsideListMarker`. It is a block-level box that is a child of the `LayoutNGListItem`, but flagged via `IsLayoutNGOutsideListMarker()`.
2. **Fragment Generation**: During `NGBlockLayoutAlgorithm::Layout`, when the algorithm encounters a child where `child.IsListMarker()` is true, it does **not** advance the block-offset (BFC offset) or include it in the standard inflow children loop. Instead, it invokes `NGUnpositionedListMarker(LayoutNGOutsideListMarker)` to hold the node in a pending state.
3. **Relative Out-of-Flow Offset**:
   * The list item layouts its normal inflow children (blocks or line boxes).
   * As soon as the first line box with content (or the first non-empty block child) is generated, its baseline and BFC block-offset are captured.
   * `NGUnpositionedListMarker::AddToBox` is invoked. The marker is laid out with an unconstrained inline available size (`kIndefiniteSize`), generating an `NGPhysicalBoxFragment`.
   * The marker fragment is placed at an inline offset strictly prior to the content box edge (in LTR, a negative X offset relative to the list item's content box; in RTL, a positive X offset beyond the content box width).

---

### 3. Sizing, Margin Offsets, and Baseline Alignment

#### Intrinsic Text Extent
For `kLanguage` and `kStaticString`, the marker's inline size $w_{\text{marker}}$ is the exact advance width of the shaped `NGTextFragment` (computed via HarfBuzz in `ShapingLineBreaker`), which includes the counter representation and the counter suffix (e.g., `"1."` + `" "` in standard UA styles, or `"1."` without space if using legacy margin-based spacing).

For `kSymbol`, Blink computes intrinsic dimensions directly from the primary `SimpleFontData` metrics of the list item's `FontMetrics`:
$$\text{Ascent } (A) = \text{font\_metrics.Ascent()}$$
$$\text{Width}_{\text{symbol}} = \text{Height}_{\text{symbol}} = \left\lfloor \frac{A \times 2}{3} \right\rfloor \quad (\text{historically, or } \approx 0.35\text{em in modern symbol paths})$$

#### Margin Offset Calculation (`ListMarker::InlineMarginsFor...`)
When `::marker` does not have author-specified `margin-inline`, Blink synthesizes margins based on `ListStyleCategory`:

* **Inside Margins (`InlineMarginsForInside`)**:
  * **Image**: $\text{margin}_{\text{start}} = 0$, $\text{margin}_{\text{end}} = \text{kCMarkerPaddingPx} \text{ (typically } 3\text{px or } 0.5\text{em)}$.
  * **Symbol**:
    $$\text{margin}_{\text{start}} = -1\text{px}$$
    $$\text{margin}_{\text{end}} = \text{ Ascent } \times \text{symbol\_margin\_factor}$$
  * **Language / Text**: $\text{margin}_{\text{start}} = 0$, $\text{margin}_{\text{end}} = 0$ (since CSS Lists 3 incorporates the trailing space directly into the `@counter-style` `suffix: ". "` descriptor).

* **Outside Margins (`InlineMarginsForOutside`)**:
  The invariant for outside markers is that the right edge of the marker box (including its end margin) aligns with the start edge of the list item's content (or first line box). Thus, the sum of the marker's width and its inline margins must equal $0$:
  $$w_{\text{marker}} + \text{margin}_{\text{start}} + \text{margin}_{\text{end}} = 0$$
  * **Text / Language**:
    $$\text{margin}_{\text{start}} = -w_{\text{marker}}$$
    $$\text{margin}_{\text{end}} = 0$$
    (Because the suffix `" "` is part of $w_{\text{marker}}$, the visual gap is baked into the text advance width).
  * **Symbol**:
    Given font ascent $A$, Blink places the symbol at a proportional offset from the content edge:
    $$\text{margin}_{\text{start}} = -\left( w_{\text{marker}} + \text{offset}_{\text{symbol}} \right)$$
    $$\text{margin}_{\text{end}} = \text{offset}_{\text{symbol}}$$
  * **Image**:
    $$\text{margin}_{\text{end}} = \text{kCMarkerPaddingPx}$$
    $$\text{margin}_{\text{start}} = -\left( w_{\text{marker}} + \text{margin}_{\text{end}} \right)$$

#### Baseline Alignment
Let $B_{\text{content}}$ be the block-offset of the first line box's alphabetic (or ideographic) baseline relative to the `LayoutNGListItem` border box, and $B_{\text{marker}}$ be the internal baseline of the marker fragment (for text, its font ascent; for an image, its physical height $h_{\text{marker}}$).

In `NGUnpositionedListMarker::AddToBox`, the block-offset $y_{\text{marker}}$ of the outside marker is resolved as:
$$y_{\text{marker}} = B_{\text{content}} - B_{\text{marker}}$$

If the list item contains **no line boxes** (e.g., `<li><div></div></li>` where the `div` is empty, or `<li></li>`), $B_{\text{content}}$ falls back to the list item's `BorderAndPadding().block_start` plus the marker's own font ascent $A_{\text{marker}}$, yielding:
$$y_{\text{marker}} = \text{border\_block\_start} + \text{padding\_block\_start}$$

---

### 4. Counter String Formatting and Symbol Resolution

Blink implements the W3C CSS Counter Styles Level 3 specification via the `CounterStyle` class (`third_party/blink/renderer/core/css/counter_style.h`).

#### Ordinal Value Resolution (`ListItemOrdinal`)
Each `LayoutNGListItem` (or DOM `HTMLLIElement`) maintains a `ListItemOrdinal`. If an explicit `value` attribute is absent, the ordinal value $V \in \mathbb{Z}$ is computed by walking the flat layout/DOM tree backwards within the enclosing `<ol>`/`<ul>` scope, incrementing by $1$ (or decrementing if `<ol reversed>`).

#### String Generation Pipeline
When `ListMarker::UpdateMarkerTextIfNeeded` executes:
1. It fetches the `CounterStyle` matching `style.ListStyleType()`.
2. It invokes `CounterStyle::GenerateRepresentation(int value)`:
   * **Predefined Symbols (`disc`, `circle`, `square`)**: Configured with `system: cyclic`. Irrespective of $V$, it returns the single code point in the descriptor list:
     * `disc` $\to$ `\u2022` (BULLET `•`)
     * `circle` $\to$ `\u25E6` (WHITE BULLET `◦`)
     * `square` $\to$ `\u25AA` (BLACK SMALL SQUARE `▪`)
   * **`decimal`**: Configured with `system: numeric` and symbols `'0'..'9'`.
     * For $V = 0$, returns `"0"`.
     * For $V > 0$, repeatedly extracts $d = V \bmod 10$, maps to symbol, prepends, and sets $V \leftarrow \lfloor V / 10 \rfloor$.
     * For $V < 0$, computes representation for $|V|$ and prepends the `negative` descriptor (default `"-"`).
3. **Prefix and Suffix Attachment**:
   $$\text{Text}_{\text{final}} = \text{Prefix} \mathbin{\Vert} \text{Representation}(V) \mathbin{\Vert} \text{Suffix}$$
   For standard `decimal`, `Prefix` is `""` and `Suffix` is `". "` (U+002E followed by U+0020). For `disc`, `Suffix` is `" "` (U+0020).

---

### 5. Formal Invariants

Let the coordinate space be localized to the `LayoutNGListItem` border box in a horizontal-tb, Left-to-Right (LTR) writing mode. Let:
* $x_{\text{content}} = \text{border}_{\text{left}} + \text{padding}_{\text{left}} + \text{line\_offset}_{\text{inline}}$ be the inline start offset of the list item's first line box.
* $w_{\text{marker}}$ be the physical inline size of the marker fragment.
* $m_{\text{start}}, m_{\text{end}}$ be the resolved inline start and end margins of the marker.
* $x_{\text{marker}}$ be the resolved inline offset of the marker fragment.

#### Invariant 1: Marker Width Non-Negativity
The intrinsic layout calculation of any marker (Symbol, Language, or Image) strictly yields a non-negative physical width in `LayoutUnit`s:
$$\forall m \in \text{ListMarker}, \quad w_{\text{marker}}(m) \ge 0$$

#### Invariant 2: Outside Offset Equation and Non-Overlap
For an `outside` list marker attached to a standard inflow