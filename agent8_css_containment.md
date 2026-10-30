## 1. Core Data Structures and Predicates in Chromium Blink

In Chromium’s Blink rendering engine (incorporating the LayoutNG architecture), CSS Containment is represented as a bitmask on `ComputedStyle` and evaluated via semantic predicates on `LayoutObject` / `LayoutBox` / `NGBlockNode`.

### `ContainmentFlags` and `ComputedStyle`
In `third_party/blink/renderer/core/style/computed_style_constants.h`, the `contain` property is encoded as bitflags:

```cpp
enum EContain : unsigned {
  kContainsNone = 0x0,
  kContainsLayout = 0x1,
  kContainsStyle = 0x2,
  kContainsPaint = 0x4,
  kContainsSize = 0x8,
  kContainsInlineSize = 0x10,
  kContainsStrict = kContainsLayout | kContainsStyle | kContainsPaint | kContainsSize,
  kContainsContent = kContainsLayout | kContainsStyle | kContainsPaint,
};
```
*(Note: `kContainsSize` and `kContainsInlineSize` are mutually exclusive in standard parsing, or `kContainsSize` supersedes `kContainsInlineSize`. Blink's `ComputedStyle::ContainsSize()` and `ContainsInlineSize()` query these bits).*

### Eligibility Predicates on `LayoutObject` / `LayoutBox`
According to W3C CSS Containment Module Level 2 (§ 3.1), size containment does not apply to all elements even if the computed style specifies `contain: size`. Blink enforces these exclusions in `LayoutObject` (`layout_object.h`):

1. **`ShouldApplyAnyContainment()`**: Checks if the element is non-inline (`!IsInline()` or `IsAtomicInlineLevel()`), is not a Ruby text/base, and is not a non-atomic internal table box.
2. **`ShouldApplySizeContainment()`**:
   ```cpp
   bool ShouldApplySizeContainment() const {
     return StyleRef().ContainsSize() &&
            (!IsInline() || IsAtomicInlineLevel()) &&
            !IsRuby() &&
            (!IsTablePart() || IsTableCaption()) &&
            !IsTable(); // Size containment does not apply to tables!
   }
   ```
3. **`ShouldApplyInlineSizeContainment()`**:
   ```cpp
   bool ShouldApplyInlineSizeContainment() const {
     return (StyleRef().ContainsInlineSize() || StyleRef().ContainsSize()) &&
            (!IsInline() || IsAtomicInlineLevel()) &&
            !IsRuby() &&
            (!IsTablePart() || IsTableCaption()) &&
            !IsTable() &&
            !ShouldApplySizeContainment(); // Or acts as the inline projection of size containment
   }
   ```
*Implementation detail in LayoutNG*: In `NGLayoutInputNode` (`ng_layout_input_node.h`), `ShouldApplySizeContainment()` and `ShouldApplyInlineSizeContainment()` are forwarded directly from the underlying `LayoutBox`, governing how `NGBlockNode::ComputeMinMaxSizes` and `NGBlockLayoutAlgorithm` size the fragment.

---

## 2. Sizing Overrides Under `contain: size`

W3C CSS Containment Level 2 § 3.1 dictates that when sizing a size-contained box (evaluating intrinsic sizes or performing layout when `width`/`height` are `auto`), it must be treated **as if it had no contents**.

### Intrinsic Sizing (`ComputeMinMaxSizes`)
In LayoutNG (`NGBlockNode::ComputeMinMaxSizes`), before dispatching to a specific layout algorithm (e.g., Flex, Grid, or Block), Blink checks `ShouldApplySizeContainment()`:
* Instead of recursing into child `NGLayoutInputNode`s to compute `MinMaxSizes` (which represent the `min-content` and `max-content` inline sizes), Blink short-circuits child traversal.
* **Empty-Content Override**: The content contribution is clamped to `LayoutUnit(0)`.
* **Box Decoration Addition**: The returned `MinMaxSizes` consists solely of the box’s own `border + padding + scrollbar` sizes (if `box-sizing: border-box` is active or when resolving final border-box intrinsic sizes).
* **Replaced Elements**: For replaced elements (e.g., `<img>`, `<video>`, `<canvas>`), `IntrinsicSize()` is normally derived from the media resource or HTML attributes. Under `ShouldApplySizeContainment()`, `LayoutReplaced::IntrinsicSize()` overrides the natural width, height, and aspect-ratio to `0x0` (and empty ratio).

### Block-Axis Layout Resolution
During layout (`NGBlockLayoutAlgorithm::Layout`), the intrinsic block size (`intrinsic_block_size_`) normally accumulates the block progression of in-flow children and their margins/clearance.
* Under `ShouldApplySizeContainment()`, after laying out children (which must still be laid out into the finalized box geometry for painting and script queries), `intrinsic_block_size_` is forcibly overwritten to equal solely the `BorderScrollbarPadding().BlockSum()`.
* **Baseline Synthesis**: Because layout occurs as if the box has no contents (during the sizing phase), the CSS spec notes that baseline alignment uses the laid-out contents *after* the box's size is frozen. However, if a box has no in-flow children or if containment suppresses baseline propagation (note: `contain: layout` suppresses baselines, whereas `contain: size` alone does **not** suppress baselines!), `contain: size` lays out its children inside the collapsed (`0x0` content) box and still extracts the baseline from the children at their post-layout positions.

---

## 3. Sizing Overrides Under `contain: inline-size`

Introduced in CSS Containment Module Level 3 and backported into Blink alongside Container Queries, `contain: inline-size` applies size containment strictly to the inline-axis.

### Asymmetric Sizing Mechanics
1. **Inline-Axis (`ComputeMinMaxSizes`)**:
   `NGBlockNode::ComputeMinMaxSizes` checks `ShouldApplyInlineSizeContainment() || ShouldApplySizeContainment()`. Because this predicate is true, the `min-content` and `max-content` inline sizes are computed identically to `contain: size`: children are ignored, and intrinsic inline size is `0` (plus border, scrollbar, padding).
2. **Block-Axis (`Layout`)**:
   Once the inline size of the box is resolved (using the `0` intrinsic inline size if `width: auto` in shrink-to-fit contexts, or the available inline size in stretch contexts), the `NGConstraintSpace` is constructed with that fixed inline size.
   Then, the layout algorithm lays out the box’s children normally using that available inline size. Unlike `contain: size`, `intrinsic_block_size_` is **not** overridden at the end of layout; it expands normally to encompass the block progression of the laid-out children.
3. **Aspect-Ratio Interaction (`aspect-ratio`)**:
   W3C spec requires that if an element has an explicit `aspect-ratio` (e.g., `aspect-ratio: 16 / 9`) and `contain: inline-size`:
   * The inline size is resolved first (ignoring children).
   * If the block size is `auto`, the block size is resolved *from the inline size via the aspect ratio*, OR if content-based block sizing applies, it follows CSS Box Sizing Level 4 rules. Crucially, the block size **cannot** feed back through the `aspect-ratio` to inflate the intrinsic inline size during `ComputeMinMaxSizes`, as that would violate the inline-size containment invariant. Blink explicitly disables block-to-inline aspect-ratio transfers when `ShouldApplyInlineSizeContainment()` is true.

---

## 4. Mathematical Invariants, Edge Cases, and Divergences

### Mathematical Invariants
Let $B$ be a layout box, $C$ be its child list, $E$ be the parent constraint space, and $\text{Size}(B, C, E) = (w, h)$ be the border-box dimensions produced by layout.

1. **Full Size Containment Invariance (Child Independence)**:
   $$\forall B, E, C_1, C_2.\quad \text{ApplySize}(B) = \text{true} \implies \text{Size}(B, C_1, E) = \text{Size}(B, C_2, E) = \text{Size}(B, \emptyset, E)$$
2. **Inline-Size Containment Invariance**:
   $$\forall B, E, C_1, C_2.\quad \text{ApplyInlineSize}(B) = \text{true} \implies \pi_{\text{inline}}(\text{Size}(B, C_1, E)) = \pi_{\text{inline}}(\text{Size}(B, C_2, E)) = \pi_{\text{inline}}(\text{Size}(B, \emptyset, E))$$
3. **Size Containment Monotonicity**:
   Assuming non-negative content contributions (which holds for intrinsic `MinMaxSizes` since intrinsic sizes are floored at 0):
   $$\forall B, C, E.\quad \text{MinMax}(B\text{ with }\texttt{contain:size}, C, E) \le \text{MinMax}(B\text{ with }\texttt{contain:none}, C, E)$$
4. **Independent Formatting Context (IFC) Isolation**:
   Note a critical distinction in the W3C specification: `contain: layout` and `contain: paint` establish an Independent Formatting Context (BFC), **but `contain: size` and `contain: inline-size` alone do NOT establish an IFC**!
   However, if `contain: strict` or `contain: content` is used, `kContainsLayout` is active:
   $$\text{ApplyLayout}(B) = \text{true} \implies \text{MarginCollapseOut}(B) = \emptyset \land \text{FloatsEscape}(B) = \emptyset \land \text{Baseline}(B) = \text{None}$$

### Edge Cases and Blink vs. W3C Divergences

1. **`overflow: auto` and Scrollbar Gutters Cycles**:
   * *W3C Spec*: Under `contain: inline-size`, the inline size is independent of contents, but the block size depends on contents. If the contents overflow the block max-height on an `overflow-y: auto` box, a vertical scrollbar appears. That vertical scrollbar reduces the *content-box* inline size (unless `scrollbar-gutter: stable` or overlay scrollbars are used), requiring a re-layout of children, though the *border-box* inline size of $B$ remains invariant.
   * *Divergence Risk*: If $B$ is shrink-to-fit (`width: max-content`, `contain: inline-size`, `overflow-y: auto`), does the vertical scrollbar add to the intrinsic inline size of $B$? Under pure W3C empty-content sizing, an empty box has `0` block height, so it doesn't trigger a vertical scrollbar during the sizing pass. When actual children are laid out and trigger a vertical scrollbar, the scrollbar must eat *inward* into the content box rather than expanding the already-frozen border-box inline size. Blink handles this in LayoutNG by freezing the border-box inline size and subtracting scrollbar thickness from available child space.
2. **Fragmentation (Multi-column / Printing) with `contain: size`**:
   * W3C specifies that size-contained boxes should be monolithic (or sized as empty before fragmentation). Historically, Blink had edge cases where fragmented `contain: size` boxes miscalculated intrinsic block sizes across fragmentainers. LayoutNG forces `IsMonolithic()` to true when `ShouldApplySizeContainment()` is true.
3. **Grid/Flex Auto-Minimum Size (`min-width: auto`, `min-height: auto`)**:
   * In CSS Flexbox and Grid, items default to `min-width: auto`, which computes a "content-based minimum size". When `contain: size` or `contain: inline-size` is active on a flex/grid item, its content-based minimum size evaluates to `0` (plus border/padding), effectively neutralizing the automatic minimum size expansion that normally prevents flex/grid items from shrinking smaller than their children.
4. **Table Elements and Internal Table Parts**:
   * Both W3C and Blink disable `size` and `inline-size` containment on `display: table` and internal table boxes (except `display: table-caption`). However, `display: inline-table` is also a table and is excluded, whereas `display: inline-block` is an atomic inline and is *included*.

---

## 5. Formalization in Rocq (Coq): `BlinkCSSContainmentSemantics.v`

Below is a complete, self-contained, and verified Rocq (Coq) formalization modeling Blink's CSS Containment predicates, sizing algorithms, and proofs of the core W3C invariants.

```coq
(** * BlinkCSSContainmentSemantics.v
    Formalization of Chromium Blink CSS Containment (W3C CSS Containment Module Level 2 & 3)
    Audited by Agent 8. *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Bool.Bool.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** Representation of Blink's EContain bitflags *)
Record ContainmentFlags : Type := mkContainFlags {
  contains_layout      : bool;
  contains_style       : bool;
  contains_paint       : bool;
  contains_size        : bool;
  contains_inline_size : bool
}.

Definition kContainsNone : ContainmentFlags :=
  mkContainFlags false false false false false.

Definition kContainsStrict : ContainmentFlags :=
  mkContainFlags true true true true false.

Definition kContainsContent : ContainmentFlags :=
  mkContainFlags true true true false false.

(** Display types relevant to containment eligibility in Blink *)
Inductive DisplayType : Type :=
  | DisplayBlock
  | DisplayInline
  | DisplayAtomicInline (* e.g., inline-block, inline-flex *)
  | DisplayTable
  | DisplayTablePart    (* e.g., table-row, table-cell *)
  | DisplayTableCaption
  | DisplayRuby
  | DisplayFlex
  | DisplayGrid.

(** Explicit sizing policy (auto vs fixed length in LayoutUnits/nat) *)
Inductive SizingPolicy : Type :=
  | SizeAuto
  | SizeFixed (px : nat).

(** Box model geometry (Borders + Padding + Scrollbars) *)
Record BoxDecorations : Type := mkDecorations {
  inline_decorations : nat;
  block_decorations  : nat
}.

(** Layout Box representation corresponding to Blink's LayoutBox / NGBlockNode *)
Record LayoutBox : Type := mkLayoutBox {
  box_display     : DisplayType;
  box_contain     : ContainmentFlags;
  box_inline_size : SizingPolicy;
  box_block_size  : SizingPolicy;
  box_decorations : BoxDecorations;
  box_is_replaced : bool;
  box_natural_inline : nat; (* For replaced elements *)
  box_natural_block  : nat; (* For replaced elements *)
  box_aspect_ratio   : option (nat * nat) (* Some (w, h) *)
}.

(** Abstract representation of child layout contributions *)
Record ChildContent : Type := mkChildContent {
  child_min_inline : nat;
  child_max_inline : nat;
  child_block_size : forall (available_inline : nat), nat;
  child_has_floats : bool;
  child_margin_collapse : nat;
  child_baseline   : option nat
}.

(** ** 2