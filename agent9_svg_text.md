### 1. Core Data Structures in Blink SVG Text (LayoutNG Architecture)

In Chromium's Blink rendering engine (post-LayoutNG SVG Text unification), SVG text layout is managed by a specialized inline formatting context orchestrated by `LayoutSVGText` and `SVGTextLayoutAlgorithm`. The historical legacy classes (`SVGTextChunk`, `SVGTextFragment`) have been superseded by an explicit per-character state array (`Vector<SvgPerCharacterInfo>`) and `NGLogicalLineItems`.

#### `LayoutSVGText` (`third_party/blink/renderer/core/layout/svg/layout_svg_text.h`)
The root layout object for an `<svg:text>` element. It inherits from `LayoutBlockFlow` (integrating with the LayoutNG block/inline pipeline) rather than `LayoutSVGBlock`.
*   **Responsibilities:** Tracks dirty flags (`needs_text_metrics_update_`), triggers `SVGTextLayoutAttributesBuilder` during layout collection, and delegates inline layout to `SVGTextLayoutAlgorithm`.
*   **Invariants:** Must be the root of the SVG inline formatting context; nested `<tspan>` and `<textPath>` elements are represented as `LayoutSVGInline` children within its `NGInlineNode` subtree.

#### `SVGInlineNode` / `NGInlineNode` & `SVGTextLayoutAttributesBuilder`
Before running the layout algorithm, `SVGTextLayoutAttributesBuilder` traverses the DOM/Layout tree under `LayoutSVGText` to flatten hierarchical positioning attributes (`x`, `y`, `dx`, `dy`, `rotate`) onto a unified UTF-16 code unit stream (`NGInlineNodeData::text_content`).
*   **Data Output (`SvgInlineNodeData`):** Produces a vector of `SvgCharacterData` mappings paired with character indices, resolving hierarchical cascade semantics (an ancestor `<text>`'s `x="10 20 30"` is overridden by a child `<tspan>`'s `x="50"` at the corresponding character index, but resumes for subsequent characters if the `<tspan>` list is shorter).

#### `SVGTextLayoutAlgorithm` (`third_party/blink/renderer/core/layout/svg/svg_text_layout_algorithm.h`)
The core engine implementing W3C SVG 2 §11.4 ("Text layout"). It operates on a single flattened `NGLogicalLineItems` list produced by shaping the entire `<text>` element as a continuous paragraph (ignoring CSS line-breaking unless `inline-size` is specified).
*   **Internal State (`SvgPerCharacterInfo`):** The algorithm unpacks the shaped `NGFragmentItem`s into a contiguous array of `SvgPerCharacterInfo` structs—one per addressable typographic character (grapheme cluster / addressable UTF-16 code point).
    ```cpp
    struct SvgPerCharacterInfo {
      absl::optional<float> x;
      absl::optional<float> y;
      absl::optional<float> dx;
      absl::optional<float> dy;
      absl::optional<float> rotate;
      bool middle = false;          // True if continuation of a multi-code-unit grapheme/ligature
      bool anchored_chunk = false;  // True if this character initiates a new "text chunk"
      bool in_text_path = false;
      float baseline_shift = 0.0f;
      // Resolved physical/logical layout coordinates:
      float inline_offset = 0.0f;
      float block_offset = 0.0f;
    };
    ```

#### `SVGTextFragment` and `SVGTextChunk` (Conceptual & Physical Realization)
In the LayoutNG architecture:
*   **`SVGTextFragment`:** Realized as individual `NGLogicalLineItem` / `NGFragmentItem` instances (of type `kSvgText`). After `SVGTextLayoutAlgorithm` resolves per-character coordinates, it splits any multi-character shaped text `NGLogicalLineItem` into atomic per-glyph/per-cluster `NGLogicalLineItem`s, attaching a ` NGSVGFragmentData` containing the exact transformed physical bounding rect (` gfx::RectF`), rotation angle, and length-adjust scale matrix.
*   **`SVGTextChunk`:** Represented implicitly during `SVGTextLayoutAlgorithm::AdjustPositions()` and `ApplyTextAnchor()` as contiguous index ranges `[chunk_start, chunk_end)` over the `result_` (`Vector<SvgPerCharacterInfo>`) array where `result_[chunk_start].anchored_chunk == true` and `result_[i].anchored_chunk == false` for $i \in (\text{chunk\_start}, \text{chunk\_end})$.

---

### 2. SVG Text Chunk Building and Glyph Positioning Algorithm

Blink implements the SVG 2 §11.4.4 "Text layout algorithm" inside `SVGTextLayoutAlgorithm::Layout()`. The execution proceeds through six strict phases over $N$ addressable characters:

#### Phase 1: Flagging Addressable Characters & Resolving Attributes (`Setup()`)
1. Iterate over the shaped `NGLogicalLineItems`. Identify grapheme clusters and ligatures. Mark continuation characters with `info.middle = true` (unaddressable).
2. Map the sparse `SvgCharacterData` list onto the `result_` vector of size $N$.
3. **Chunk Boundary Assignment:**
   * `result_[0].anchored_chunk = true;`
   * For $i \in [1, N)$: If `result_[i].x.has_value()` (in horizontal writing mode) or `result_[i].y.has_value()` (in vertical writing mode), and `!result_[i].middle`, set `result_[i].anchored_chunk = true`.
   * *Note on Deviation:* SVG 2 §11.4.2 specifies that *either* an explicit `x` *or* `y` attribute starts a new text chunk regardless of writing mode. Blink actually sets `anchored_chunk = data.HasX() || data.HasY()` in `SVGTextLayoutAlgorithm::SetFlags()` to maintain full compliance with SVG 1.1/2.0 chunk definitions.

#### Phase 2: Initial Coordinate & Delta Resolution (`AdjustPositions()`)
Maintain running current text position $(CTP_x, CTP_y)$, initialized to $(0, 0)$.
For each character $i \in [0, N)$:
1. If `result_[i].middle == true`, inherit offsets from $i-1$ and continue.
2. **Resolve Explicit Coordinates:**
   $$X_i = \begin{cases} \text{result}[i].x & \text{if } \text{result}[i].x \neq \text{nullopt} \\ CTP_x & \text{otherwise} \end{cases}$$
   $$Y_i = \begin{cases} \text{result}[i].y & \text{if } \text{result}[i].y \neq \text{nullopt} \\ CTP_y & \text{otherwise} \end{cases}$$
3. **Apply Relative Shifts (`dx`, `dy`):**
   $$\Delta X_i = \text{result}[i].dx.\text{value\_or}(0.0), \quad \Delta Y_i = \text{result}[i].dy.\text{value\_or}(0.0)$$
   $$\text{pos}_x[i] = X_i + \Delta X_i$$
   $$\text{pos}_y[i] = Y_i + \Delta Y_i + \text{baseline\_shift}_i$$
4. **Advance Current Text Position:**
   Let $A_i$ be the shaped inline advance of character $i$ (scaled by `font-size` and CSS `letter-spacing`/`word-spacing`).
   * In horizontal mode:
     $$CTP_x = \text{pos}_x[i] + A_i, \quad CTP_y = Y_i + \Delta Y_i$$
   * In vertical mode:
     $$CTP_x = X_i + \Delta X_i, \quad CTP_y = \text{pos}_y[i] + A_i$$

#### Phase 3: `textLength` Adjustment (`ApplyTextLengthAttribute()`)
Before anchor shifts, if `<text>` or `<tspan>` specifies `textLength`, Blink computes the min/max bounding positions of the target range $[j, k)$ and scales either spacing (`lengthAdjust="spacing"`) or both spacing and glyph advances (`lengthAdjust="spacingAndGlyphs"`).

#### Phase 4: Text Chunk Partitioning & `text-anchor` Adjustment (`ApplyTextAnchor()`)
Partition $[0, N)$ into maximal contiguous ranges $C_m = [s_m, e_m)$ where `result_[s_m].anchored_chunk == true` and $\forall i \in (s_m, e_m), \text{result\_}[i].\text{anchored\_chunk} == \text{false}$.

For each chunk $C_m = [s_m, e_m)$:
1. Compute the geometric bounds of the chunk along the inline advance axis (let $P_i$ be $\text{pos}_x[i]$ for horizontal, $\text{pos}_y[i]$ for vertical):
   $$a = \min_{i \in [s_m, e_m)} (P_i, P_i + A_i)$$
   $$b = \max_{i \in [s_m, e_m)} (P_i, P_i + A_i)$$
   *(Note: Taking $\min/\max$ of both $P_i$ and $P_i + A_i$ handles RTL glyphs or negative advances, though in Blink standard shaped advances $A_i \ge 0$, so $a = \min P_i$ and $b = \max (P_i + A_i)$).*
2. Determine the `text-anchor` property of the DOM node owning character $s_m$ ( combined with the chunk's CSS `direction`: `ltr` vs `rtl`).
3. Calculate the scalar shift $\Delta_{\text{anchor}}$:
   * **Effective Start** (`(ltr && start) || (rtl && end)`):
     $$\Delta_{\text{anchor}} = 0$$
   * **Middle** (`middle`):
     $$\Delta_{\text{anchor}} = -\frac{(a + b) - 2 P_{s_m}}{2} = P_{s_m} - \frac{a + b}{2}$$
   * **Effective End** (`(ltr && end) || (rtl && start)`):
     $$\Delta_{\text{anchor}} = P_{s_m} - (b - a) - P_{s_m} = -(b - a) \quad \text{(if } a = P_{s_m}\text{, else } P_{s_m} - b\text{)}$$
     *(Specifically, SVG 2 §11.4.4 Step 5 states: for start, shift by $P_{s_m} - a$; for middle, shift by $P_{s_m} - (a+b)/2$; for end, shift by $P_{s_m} - b$.)*
4. Apply shift to all characters in the chunk:
   $$\forall i \in [s_m, e_m), \quad P_i \leftarrow P_i + \Delta_{\text{anchor}}$$

---

### 3. Text Chunk Bi-Directional Reordering and Anchor Offset Shifts

#### Interaction Between UAX #9 (Bidi) and SVG Text Chunks
A critical complexity in SVG 2 §11.4 is the interplay between **logical order** (DOM character order, in which `x`, `y`, `dx`, `dy`, `rotate` lists are indexed) and **visual order** (the order after Unicode Bidirectional Algorithm UAX #9 reordering).

1. **Bidi Resolution Before Positioning:**
   In Blink's LayoutNG pipeline, `NGInlineNode::PrepareLayout()` runs ICU's BiDi algorithm (`UBiDi`) and HarfBuzz shaping **before** `SVGTextLayoutAlgorithm` executes. Consequently, the `NGLogicalLineItems` passed to `SVGTextLayoutAlgorithm` are already reordered into **visual order** (left-to-right for horizontal lines), and glyphs within RTL runs are reversed.
2. **Logical-to-Visual Attribute Mapping:**
   * According to SVG 2 §11.4.4, `x`, `y`, `dx`, `dy`, and `rotate` attributes are assigned to characters in **logical order** (DOM order).
   * However, the positioning loop (`AdjustPositions`, which accumulates $CTP_x \leftarrow \text{pos}_x + A_i$) iterates in **visual order** (the order of items in `NGLogicalLineItems`), *except* when resolving which character starts an anchored chunk!
   * In Blink (`SVGTextLayoutAlgorithm::Setup`), each visual character item retains its logical `TextOffset` into `NGInlineNodeData::text_content`. Blink maps the logical `SvgCharacterData` onto the visual `result_` array using this logical offset.
3. **Chunk Boundaries Under Bidi:**
   * If a logical character $k$ has an explicit `x` attribute, it is marked `anchored_chunk = true`.
   * When reordered into visual index $v(k)$, `result_[v(k)].anchored_chunk` becomes `true`.
   * **Crucial Consequence:** In Blink, because `result_` is ordered visually, text chunks are partitioned as contiguous **visual** slices $[v_s, v_e)$ between characters flagged with `anchored_chunk`, rather than contiguous **logical** slices!
   * *Wait—does SVG 2 require logical or visual chunk partitioning?*
     SVG 2 §11.4.2 states: *"Text chunks are defined before bidirectional reordering... Each text chunk is an independent directional run for bidirectional reordering."*
     If each text chunk is an independent Bidi paragraph/run, then a chunk cannot be split into non-contiguous visual pieces by Bidi reordering! However, in Blink, `NGInlineNode` runs Bidi across the **entire `<text>` element** as a single paragraph before `SVGTextLayoutAlgorithm` even sees the `x`/`y` chunk boundaries.

#### Anchor Offset Shift Math with RTL (`direction: rtl`)
Let the chunk's governing CSS `direction` be $D \in \{\text{LTR}, \text{RTL}\}$ and `text-anchor` be $T \in \{\text{start}, \text{middle}, \text{end}\}$. Let $O = P_{s_m}$ be the initial origin of the chunk (the explicit `x` or `y` coordinate assigned to the chunk's initial character), and $[a, b]$ be the bounding interval of the chunk's glyphs.

Per W3C SVG 2 §11.4.4:
$$\text{shift}(D, T, O, a, b) = \begin{cases} 
O - a & \text{if } (D = \text{LTR} \land T = \text{start}) \lor (D = \text{RTL} \land T = \text{end}) \\
O - \frac{a + b}{2} & \text{if } T = \text{middle} \\
O - b & \text{if } (D = \text{LTR} \land T = \text{end}) \lor (D = \text{RTL} \land T = \text{start})
\end{cases}$$

After shifting every glyph $i \in C_m$ by $\text{shift}(D, T, O, a, b)$:
* The new minimum bound is $a' = a + \text{shift}$.
* The new maximum bound is $b' = b + \text{shift}$.
* For LTR `start` (or RTL `end`): $a