### 1. Core Data Structures in Blink Form Control Layout

In Chromium’s Blink LayoutNG architecture, form controls (`<input>`, `<textarea>`, `<select>`) are replaced elements with complex internal shadow DOM structures. Rather than using legacy `LayoutTextControl` hierarchies directly for geometry, LayoutNG maps these DOM nodes into specialized box fragments and layout algorithms while retaining specific DOM/Layout object roles for style resolution and inner-editor management.

```
+-------------------------------------------------------------------------+
| HTMLInputElement / HTMLTextAreaElement (Host DOM Node)                  |
| LayoutObject: LayoutBlockFlow (with IsTextControl() / IsTextField())    |
+-------------------------------------------------------------------------+
       |
       | (User-Agent Shadow Root)
       v
+-------------------------------------------------------------------------+
|div pseudo="-webkit-input-placeholder" / Container (Optional Flex/Grid)  |
+-------------------------------------------------------------------------+
       |
       v
+-------------------------------------------------------------------------+
| TextControlInnerEditorElement (Shadow DOM Node)                         |
| LayoutObject: LayoutTextControlInnerEditor (inherits LayoutBlockFlow)   |
| CSS: overflow-x: scroll; overflow-y: hidden (SingleLine)                |
|      overflow: auto; white-space: pre-wrap (MultiLine)                  |
+-------------------------------------------------------------------------+
       |
       v
+-------------------------------------------------------------------------+
| Inline Formatting Context (NGInlineNode)                                |
| -> LineBox Fragments -> Text Fragments (Actual Glyphs / Brutal Metrics) |
+-------------------------------------------------------------------------+
```

#### `HTMLTextControlElement` & `TextControlInnerEditorElement` (DOM & Style Layer)
* **`HTMLTextControlElement`**: The base C++ class for `HTMLInputElement` (when `type` is text-based) and `HTMLTextAreaElement`. It manages the UA Shadow Root.
* **`TextControlInnerEditorElement`**: The core shadow DOM `<div>` (`::-webkit-textfield-decoration-container` -> inner editor) that holds the editable text nodes. It receives inherited font and line-height styles from the host control, alongside specific user-agent rules (`-webkit-user-modify: read-write-plaintext-only`).

#### `NGBlockNode` & `NGPhysicalBoxFragment` (LayoutNG Core)
In LayoutNG, legacy `LayoutTextControlSingleLine` and `LayoutTextControlMultiLine` have been unified into standard `LayoutBlockFlow` instances configured with specific `ComputedStyle` flags (e.g., `EDisplay::kInlineBlock`, `ControlPart`).
* **`NGBlockLayoutAlgorithm`**: Executes layout for the host form control and the inner editor.
* **`NGPhysicalBoxFragment`**: The immutable output of a layout pass. It stores:
  * `size_`: The physical border-box dimensions (`LayoutUnit` width and height).
  * `first_baseline_`: `std::optional<LayoutUnit>` representing the distance from the fragment’s block-start border edge to the first alphabetic/ideographic baseline.
  * `last_baseline_`: `std::optional<LayoutUnit>` for `baseline-source: last`.
  * `use_last_baseline_for_inline_baseline_`: Boolean flag distinguishing `<textarea>` versus `<input>` baseline export behaviors in specific writing modes.

#### `FontMetrics` & `FontHeight` (Typography Primitives)
* **`FontHeight`**: A tuple `(LayoutUnit ascent, LayoutUnit descent)` representing the typographic metrics of the primary font on the control’s `ComputedStyle`.
* **`LineBoxStrut`**: Used during inline layout of the `TextControlInnerEditorElement` to compute the height of the line box even when the input value is the empty string `""`.

---

### 2. Intrinsic Baseline Calculation Algorithm

The baseline of a form control governs how it aligns with adjacent inline-level boxes within an Inline Formatting Context (CSS Box Alignment Module Level 3, §9; HTML Standard §15.3.5 / §4.10).

#### A. Single-Line Text Inputs (`<input type="text|search|tel|url|email|password|number">`)
Single-line inputs establish an inline-block formatting context. Internally, they may use a flexbox-like container if decorations (spin buttons, clear buttons, search icons) are present, or a direct block container wrapping the `TextControlInnerEditorElement`.

**Algorithm (`NGBoxFragmentBuilder::ComputeBaseline` / `NGBlockLayoutAlgorithm::ComputeBaseline`):**
1. **Inner Editor Line Box Extraction:**
   The layout engine traverses the child fragments of the host `<input>`. It locates the `TextControlInnerEditorElement` fragment.
2. **Non-Empty Line Box Case:**
   If the inner editor generated at least one `NGPhysicalLineBoxFragment` (which is true even for empty inputs because Blink forces a placeholder strut via `TextControlInnerEditorElement` layout rules):
   $$\text{Baseline}_{\text{raw}} = \text{Offset}_{\text{block}}(\text{InnerEditor}) + \text{Offset}_{\text{block}}(\text{LineBox}_0) + \text{Ascent}(\text{LineBox}_0)$$
   where $\text{Offset}_{\text{block}}(\text{Child})$ is the block-axis physical offset of the child fragment relative to its parent’s border-box origin.
3. **Empty / Fallback Case (Synthesized Font Baseline):**
   If the inner editor has `display: none` or fails to produce a line box (e.g., `content-visibility: hidden` or layout containment edge cases), Blink synthesizes the baseline directly from the host’s `ComputedStyle` font metrics, centered within the content box:
   $$\text{LineHeight} = \text{HostStyle.ComputedLineHeight()}$$
   $$\text{Ascent} = \text{HostStyle.GetFont().PrimaryFont()->GetFontMetrics().FixedAscent()}$$
   $$\text{Leading} = \text{LineHeight} - (\text{Ascent} + \text{Descent})$$
   $$\text{Baseline}_{\text{fallback}} = \text{Border}_{\text{top}} + \text{Padding}_{\text{top}} + \left\lfloor \frac{\text{ContentBoxHeight} - \text{LineHeight}}{2} \right\rfloor + \left\lfloor \frac{\text{Leading}}{2} \right\rfloor + \text{Ascent}$$

#### B. Multi-Line Text Controls (`<textarea>`)
According to CSS Box Alignment Level 3 and HTML UA stylesheet rules, `<textarea>` is an `inline-block` element with `overflow: auto` (or `scroll`). 

Per CSS 2.1 §10.8.1, the baseline of an `inline-block` whose `overflow` property has a computed value other than `visible` is the **bottom margin edge**. However, **HTML Standard §15.3.5** and **CSS Box Alignment 3 §9.1** override this for form controls: `<textarea>` must use its first line box baseline (or synthesized first line baseline) despite having scrollable overflow!

**Blink's `<textarea>` Baseline Algorithm:**
1. **Scroll Container Bypass:**
   In `NGBoxFragment::BaselineMetrics()`, normally if `IsScrollContainer()` is true, Blink returns `std::nullopt` for the content baseline, forcing the caller (`NGInlineLayoutStateStack`) to synthesize the baseline at the `margin-end` (bottom margin edge).
   **Exception:** Blink explicitly checks `LayoutObject::IsTextControl()` or `IsTextArea()`. When true, it **ignores** the scroll container baseline suppression!
2. **First Line Baseline Propagation:**
   Blink queries the `first_baseline_` of the `TextControlInnerEditorElement` fragment.
   $$\text{Baseline}_{\text{textarea}} = \text{Border}_{\text{top}} + \text{Padding}_{\text{top}} + \text{InnerEditor.FirstBaseline}$$
   Because the inner editor of a `<textarea>` is always initialized with at least an empty text node or a `<br>` placeholder in the UA shadow tree, `InnerEditor.FirstBaseline` evaluates to:
   $$\text{InnerEditor.FirstBaseline} = \left\lfloor \frac{\text{LineHeight} - (\text{Ascent} + \text{Descent})}{2} \right\rfloor + \text{Ascent}$$
3. **Strict Fallback (`std::nullopt` -> Bottom Margin Edge):**
   If `contain: size` or `content-visibility: hidden` suppresses child layout inside the `<textarea>`, the inner editor produces no fragments. `first_baseline_` on the `<textarea>` fragment becomes `std::nullopt` (or falls back to the font metric synthesis at the top of the content box). If `std::nullopt` reaches the inline formatting context, the inline layout algorithm synthesizes the baseline at:
   $$\text{Baseline}_{\text{synthesized}} = \text{BorderBoxHeight} + \text{Margin}_{\text{bottom}}$$

---

### 3. Padding, Border, and Scrollable Inner-Editor Offset Interactions

#### Centering Mechanics in `<input>` vs Top-Alignment in `<textarea>`
A critical architectural divergence occurs in how `Padding` and `Border` interact with the inner editor’s block offset:

1. **Single-Line `<input>` Vertical Centering:**
   In Blink, `<input>` centers its inner editor vertically within the **content box** if the computed `height` is greater than the inner editor's intrinsic height (which equals one `line-height`).
   Let $H_{\text{content}}$ be the content-box height of the `<input>`, and $H_{\text{editor}}$ be the border-box height of the `TextControlInnerEditorElement`.
   $$\text{Offset}_{\text{block}}(\text{InnerEditor}) = \text{Border}_{\text{top}} + \text{Padding}_{\text{top}} + \max\left(0, \left\lfloor \frac{H_{\text{content}} - H_{\text{editor}}}{2} \right\rfloor\right)$$
   Note: If $H_{\text{content}} < H_{\text{editor}}$ (e.g., the author sets `height: 10px; font-size: 20px; padding: 0;`), Blink **clamps** the centering offset or allows negative offsets depending on whether the internal container is laid out via `NGFlexLayoutAlgorithm` (when decorations exist) or `NGBlockLayoutAlgorithm`. In standard `NGBlockLayoutAlgorithm` for text inputs, if $H_{\text{content}} < H_{\text{editor}}$, the inner editor is still centered, producing a negative offset relative to the content box:
   $$\text{Offset}_{\text{block}}(\text{InnerEditor}) = \text{Border}_{\text{top}} + \text{Padding}_{\text{top}} + \left\lfloor \frac{H_{\text{content}} - H_{\text{editor}}}{2} \right\rfloor$$

2. **Multi-Line `<textarea>` Top-Alignment:**
   `<textarea>` does **not** vertically center its inner editor. The inner editor is placed strictly at the block-start of the content box:
   $$\text{Offset}_{\text{block}}(\text{InnerEditor}) = \text{Border}_{\text{top}} + \text{Padding}_{\text{top}}$$

#### Scroll Offset Invariance (Or Lack Thereof)
When a user types multiple lines into a `<textarea>` and scrolls vertically, or scrolls horizontally in an `<input>` (which might have vertical scrollbars or overflow in vertical writing modes), how does `scroll_offset` affect the baseline?

* **CSS Box Alignment 3 §9.1 Requirement:** If a scrollable box's baseline depends on its content, is it adjusted by the current scroll position, or calculated at the initial scroll position `(0, 0)`? The CSSWG resolved that intrinsic baselines of scroll containers must be evaluated at the **initial scroll position** (unscrolled) to prevent scrolling inside a `<textarea>` from violently shifting the vertical alignment of the entire surrounding line box in the parent document!
* **Blink’s Implementation (`NGPhysicalBoxFragment::Baseline()`):**
  In LayoutNG, fragments store physical offsets produced *during layout* before composited or main-thread scroll offsets (`PaintLayerScrollableArea::GetScrollOffset()`) are applied during the PrePaint/Paint phases. Therefore, `first_baseline_` cached on `NGPhysicalBoxFragment` is inherently invariant to dynamic scroll offsets!
* **The Sub-pixel / Layout-Scroll Gap:** However, if a layout pass is triggered while the inner editor has a non-zero scroll offset, does `NGBlockLayoutAlgorithm` include scroll offset in `first_baseline_`? No—scroll offsets in Blink are applied at the `PaintPropertyTreeBuilder` stage, not baked into fragment child offsets in `NGContainerFragmentBuilder`. Thus, Blink satisfies Scroll Offset Invariance for baselines.

---

### 4. Mathematical Invariants, Edge Cases, and Specification Gaps

#### Mathematical Invariants (Target Properties for Verification)

1. **Invariant 1 (Determinism):**
   For any well-formed `ControlStyle` $S$ and `ControlKind` $K \in \{\text{SingleLine}, \text{MultiLine}\}$, the baseline calculation function $\mathcal{B}(S, K)$ yields a unique, deterministic `LayoutUnit` (fixed-point integer in $\frac{1}{64}$th pixels).

2. **Invariant 2 (Monotonicity with respect to Font Ascent):**
   Holding `border`, `padding`, `content_height`, and `half_leading` constant, if $\text{Ascent}_1 \le \text{Ascent}_2$, then:
   $$\mathcal{B}(S[\text{ascent} \mapsto \text{Ascent}_1], K) \le \mathcal{B}(S[\text{ascent} \mapsto \text{Ascent}_2], K)$$

3. **Invariant 3 (Border-Box Boundedness under Non-Overflowing Geometry):**
   Let $H_{\text{border}} = \text{Border}_{\text{top}} + \text{Padding}_{\text{top}} + H_{\text{content}} + \text{Padding}_{\text{bottom}} + \text{Border}_{\text{bottom}}$.
   If $\text{Border}_{\text{top}} + \text{Padding}_{\text{top}} \ge 0$, $\text{Border}_{\text{bottom}} + \text{Padding}_{\text{bottom}} \ge 0$, $0 \le \text{Leading}$, $\text{Ascent} \ge 0$, $\text{Descent} \ge 0$, and $H_{\text{content}} \ge \text{LineHeight} = \text{Ascent} + \text{Descent} + \text{Leading}$, then the computed baseline $b = \mathcal{B}(S, K)$ is strictly bounded within the border-box:
   $$0 \le \text{Border}_{\text{top}} + \text{Padding}_{\text{top}} \le b \le H_{\text{border}}$$

#### Edge Cases & Auditing Gaps (Blink vs. Specs)

| Edge Case / Scenario | HTML / CSS Spec Requirement | Chromium Blink Behavior | Audit Status / Discrepancy |
| :--- | :--- | :--- | :--- |
| **`<input>` with `height: 0px; padding: 0px; border: 0px`** | Baseline should still be computed from the centered inner line box, resulting in a baseline $> 0$ (or $< 0$ if ascent is smaller than half line-height). | Inner editor has height $L$. Centering offset is $\lfloor (0 - L)/2 \rfloor = -\lfloor L/2 \rfloor$. Baseline is $-\lfloor L/2 \rfloor + \lfloor \text{Leading}/2 \rfloor + \text{Ascent} = \text{Ascent} - \lfloor (\text{Ascent} + \text{Descent})/2 \rfloor$. Can violate $b \le H_{\text{border}}$ ($H_{\text{border}} = 0$). | **Invariant Violation (Un