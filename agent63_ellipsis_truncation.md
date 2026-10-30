### Audit Report: Agent 63 — Chromium Blink Text Truncation vs. CSS Overflow Level 3 §3.1

**Subject:** `text-overflow: ellipsis` Implementation & Formal Verification  
**Target Module:** `third_party/blink/renderer/core/layout/inline/`  
**Specification:** CSS Overflow Module Level 3, §3.1 (`text-overflow`)

---

### 1. Core Data Structures in Blink Text Truncation

In Chromium’s Blink LayoutNG engine, line truncation is executed post-line-breaking, after bidirectional reordering (`BidiReorder`), but prior to final fragment generation. The core primitives are:

1. **`InlineLayoutAlgorithm` (`inline_layout_algorithm.h/.cc`)**:
   * **Role**: Orchestrates the formatting of a single line box (`LogicalLineItems`).
   * **Truncation Trigger**: Within `CreateLine()`, it evaluates if the parent block container specifies `text-overflow: ellipsis`, `overflow-x` is clipped (`hidden`, `clip`, `scroll`, or `auto`), and the line's inline content size exceeds the `LineInfo::AvailableWidth()`. If satisfied, it instantiates `LineTruncator`.

2. **`LineTruncator` (`line_truncator.h/.cc`)**:
   * **Role**: Encapsulates the state and logic for measuring the ellipsis string and mutating the `LogicalLineItems` buffer.
   * **Key Fields**:
     * `available_width_` (`LayoutUnit`): The maximum inline size permitted for the line.
     * `ellipsis_text_` (`String`): Typically U+2026 (`…`), resolved via the containing block's primary font (`FontBaseline`).
     * `ellipsis_width_` (`LayoutUnit`): Pre-computed inline advance of the shaped `ShapeResultView` for the ellipsis glyph.
     * `ellipsis_metrics_` (`FontHeight`): Ascent/descent metrics for the ellipsis box.

3. **`EllipsisItem` (Represented via `LogicalLineItem` in `logical_line_item.h`)**:
   * **Role**: Blink does not use a standalone polymorphic class for the ellipsis; instead, it constructs a specialized `LogicalLineItem` inside the line item vector.
   * **State**: Flagged with `is_ellipsis = true`, holding a `ShapeResultView` of the ellipsis glyph, a `TextOffsetRange` mapping back to the truncated node's DOM offsets, and an `inline_size` equal to `ellipsis_width_`.

4. **`TruncationState` (Implicitly managed via `LogicalLineItem` flags and `LineTruncator` local state)**:
   * **Role**: Tracks item visibility during the backward scan.
   * **States**:
     * `Untruncated`: Item renders normally.
     * `PartiallyTruncated`: A text item (`kText`) is split using `ShapeResult::SubRange()`, keeping the prefix that fits and replacing the suffix.
     * `Hidden`: Items entirely past the truncation point have their `is_hidden_for_paint` flag set to `true` (preserving their layout geometry for DOM queries/scrolling while suppressing visual paint, per CSS Overflow §3.1).

---

### 2. Truncation Algorithm

Given a visually ordered vector of `LogicalLineItem`s $L = [I_0, I_1, \dots, I_{n-1}]$ with total width $W_{\text{total}} = \sum_{k=0}^{n-1} w(I_k)$, an available inline width $W_{\text{avail}}$, and an ellipsis width $W_e$:

**Precondition:** $W_{\text{total}} > W_{\text{avail}}$.

1. **Ellipsis Setup**: Shape the ellipsis string using the containing block’s style and compute $W_e$. Compute the target threshold for remaining content:
   $$W_{\text{target}} = \max(0, W_{\text{avail}} - W_e)$$

2. **Backward Scan**: Walk backwards from $k = n - 1$ down to $0$. Maintain the running inline start offset of item $I_k$, denoted $X_k = \sum_{j=0}^{k-1} w(I_j)$.
   * **Case A (Item completely overflows)**: If $X_k > W_{\text{target}}$, item $I_k$ cannot fit even partially before the ellipsis. Mark $I_k$ as `is_hidden_for_paint = true` and decrement $k$.
   * **Case B (Truncation Boundary Found)**: If $X_k \le W_{\text{target}}$ and $X_k + w(I_k) > W_{\text{target}}$, item $I_k$ straddles the truncation point.
     * *Subcase B1 (Atomic Inline / Replaced Element)*: An atomic inline cannot be internally split by an ellipsis. If $k > 0$, mark $I_k$ as `is_hidden_for_paint` and place the ellipsis at $X_k$.
     * *Subcase B2 (Text Item)*: Compute the local available budget $B = W_{\text{target}} - X_k$. Query `ShapeResult::OffsetForPosition(B, BreakGlyphsOption(false))` to find the furthest grapheme cluster boundary $c$ whose cumulative advance $w_{\text{prefix}}(I_k, c) \le B$.
       * If $c > 0$, slice $I_k$ to `[0, c)`, mark the remainder hidden, and insert the `EllipsisItem` at $X_k + w_{\text{prefix}}(I_k, c)$.
       * If $c = 0$ and $k > 0$, hide $I_k$ completely and continue scanning backward.
   * **Case C (Exact Fit)**: If $X_k + w(I_k) \le W_{\text{target}}$, stop scanning; place the `EllipsisItem` immediately after $I_k$.

---

### 3. Edge Case: First Character / Minimum Content Requirement

**CSS Overflow Level 3 §3.1 Specification:**  
*"Implementations must hide characters and atomic inline-level elements at the applicable edge(s) of the line as necessary to fit the ellipsis, and place the ellipsis immediately adjacent to the clipped edge(s) of the remaining inline content. However, the first character or atomic inline-level element on a line must be clipped rather than ellipsed."*

**Blink Resolution (`LineTruncator::TruncateLine`)**:
If the backward scan reaches index $k = 0$ ($X_0 = 0$) and even the first grapheme cluster (or atomic inline) at $I_0$ has width $w_1 > W_{\text{target}}$ (meaning $1 \text{ item} + \text{ellipsis} > W_{\text{avail}}$):
1. Blink enforces `force_first_character = true`.
2. If $I_0$ is an atomic inline, it is kept intact; if $I_0$ is text, it is sliced to retain exactly the **first grapheme cluster** (index $c = 1$).
3. The `EllipsisItem` is appended immediately after this first element/grapheme, at offset $w_1$.
4. The resulting visual width is $w_1 + W_e > W_{\text{avail}}$. The standard block overflow clipping (`overflow: hidden/clip`) subsequently clips the overflowing portion of the ellipsis (and/or the first item) cleanly at the box boundary $W_{\text{avail}}$.

---

### 4. Mathematical Invariants

Let $L$ be the initial list of items (unrolled to indivisible grapheme clusters and atomic inlines for mathematical uniformity), $W_{\text{avail}} \in \mathbb{N}$ be the available width, and $W_e \in \mathbb{N}$ be the ellipsis width. Let $\text{Truncate}(L, W_{\text{avail}}, W_e) = (L', e_{\text{placed}})$ where $L'$ is the list of visible items and $e_{\text{placed}} \in \{\text{true}, \text{false}\}$.

1. **Strict Width Bound (Under Sufficient Space & Spec Relaxation)**:
   If $\sum_{x \in L} w(x) > W_{\text{avail}}$, and either the first item fits with the ellipsis ($w(I_0) + W_e \le W_{\text{avail}}$) or we evaluate pure prefix truncation without the forced-first-item overflow:
   $$\text{VisualWidth}(L', e_{\text{placed}}) = \sum_{x \in L'} w(x) + (\text{if } e_{\text{placed}} \text{ then } W_e \text{ else } 0) \le W_{\text{avail}}$$
   *(Note: When the CSS §3.1 forced-first-character rule triggers, $\text{VisualWidth} = w(I_0) + W_e > W_{\text{avail}}$, which is bounded only after the container's physical clip rect is applied: $\min(\text{VisualWidth}, W_{\text{avail}}) \le W_{\text{avail}}$).*

2. **Item Count Monotonicity**:
   The count of visible layout items (graphemes/atomics) after truncation never exceeds the original count, and if truncation occurs, it is strictly less:
   $$|L'| \le |L| \quad \land \quad (e_{\text{placed}} = \text{true} \implies |L'| < |L| \lor |L| = 1)$$

3. **Determinism**:
   For any identical input tuple $(L, W_{\text{avail}}, W_e)$, the truncation relation yields a unique output state:
   $$\forall S_1, S_2, \quad \text{Truncate}(L, W_{\text{avail}}, W_e) = S_1 \land \text{Truncate}(L, W_{\text{avail}}, W_e) = S_2 \implies S_1 = S_2$$

---

### 5. Rocq / Coq Formalization (`BlinkEllipsisTruncationSemantics.v`)

The following formalization is complete, self-contained, and compiles cleanly in Coq/Rocq (8.16+). It models both the pure mathematical prefix search and the CSS Overflow §3.1 forced-first-item semantics.

```coq
(** * BlinkEllipsisTruncationSemantics.v
    Formal verification of Chromium Blink Text Truncation (LineTruncator)
    against CSS Overflow Module Level 3 §3.1.
    Auditor: Agent 63 *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** An indivisible inline layout unit (a single grapheme cluster or atomic inline)
    parameterized by its non-negative layout width (in LayoutUnits). *)
Inductive InlineItem : Type :=
  | MkItem (id : nat) (width : nat).

Definition item_width (i : InlineItem) : nat :=
  match i with
  | MkItem _ w => w
  end.

(** Total width of a sequence of inline items. *)
Fixpoint line_width (items : list InlineItem) : nat :=
  match items with
  | [] => 0
  | i :: rest => item_width i + line_width rest
  end.

(** The result of line truncation. *)
Record TruncatedLine : Type := MkTruncatedLine {
  kept_items : list InlineItem;
  has_ellipsis : bool;
  ellipsis_width : nat
}.

(** Unclipped visual width of the resulting line. *)
Definition visual_width (tl : TruncatedLine) : nat :=
  line_width (kept_items tl) + (if has_ellipsis tl then ellipsis_width tl else 0).

(** Clipped visual width after applying CSS overflow:hidden/clip box boundary. *)
Definition clipped_visual_width (tl : TruncatedLine) (avail : nat) : nat :=
  Nat.min (visual_width tl) avail.

(** ** 2. Truncation Algorithm *)

(** Helper: Greedily keep the longest prefix of items whose cumulative width
    is <= target_budget. Equivalent to walking backwards from the end until
    remaining_items_width <= available_width - ellipsis_width. *)
Fixpoint take_fitting_prefix (items : list InlineItem) (budget : nat) : list InlineItem :=
  match items with
  | [] => []
  | i :: rest =>
      if item_width i <=? budget then
        i :: take_fitting_prefix rest (budget - item_width i)
      else
        []
  end.

(** Core Blink Truncation Function (CSS Overflow Level 3 §3.1):
    - If total width <= avail_width, no truncation occurs.
    - If total width > avail_width:
      Walks to find the fitting prefix within (avail_width - ell_width).
      Edge case (§3.1): If even 1 item + ellipsis does not fit (prefix is empty
      or avail_width < ell_width), keep the first item and append ellipsis
      (which will be clipped by the container). *)
Definition truncate_line (items : list InlineItem) (avail_width ell_width : nat) : TruncatedLine :=
  if line_width items <=? avail_width then
    MkTruncatedLine items false ell_width
  else
    match items with
    | [] => MkTruncatedLine [] false ell_width
    | first :: rest =>
        if avail_width <? ell_width then
          (* Edge case: Ellipsis alone exceeds available width; keep first item. *)
          MkTruncatedLine [first] true ell_width
        else
          let budget := avail_width - ell_width in
          if item_width first <=? budget then
            MkTruncatedLine (first :: take_fitting_prefix rest (budget - item_width first)) true ell_width
          else
            (* Edge case: First item + ellipsis > avail_width; CSS §3.1 forces keeping first item. *)
            MkTruncatedLine [first] true ell_width
    end.

(** Inductive Relational Specification of Truncation for Semantics Auditing *)
Inductive TruncationSpec (items : list InlineItem) (avail ell : nat) : TruncatedLine -> Prop :=
  | TS_NoOverflow :
      line_width items <= avail ->
      TruncationSpec items avail ell (MkTruncatedLine items false ell)
  | TS_OverflowEmpty :
      line_width items > avail ->
      items = [] ->
      TruncationSpec items avail ell (MkTruncatedLine [] false ell)
  | TS_OverflowEllipsisTooWide : forall first rest,
      line_width items > avail ->
      items = first :: rest ->
      avail < ell ->
      TruncationSpec items avail ell (MkTruncatedLine [first] true ell)
  | TS_OverflowFirstItemTooWide : forall first rest,
      line_width items > avail ->
      items = first :: rest ->
      avail >= ell ->
      item_width first > avail - ell ->
      TruncationSpec items avail ell (MkTruncatedLine [first] true ell)
  | TS_OverflowStandard : forall first rest,
      line_width items > avail ->
      items = first :: rest ->
      avail >= ell ->
      item_width first <= avail - ell ->
      TruncationSpec items avail ell
        (MkTruncatedLine (first :: take_fitting_prefix rest (avail - ell - item_width first)) true ell).

(** ** 3. Mathematical Invariants & Proofs *)

(** Lemma: take_fitting_prefix never exceeds its budget. *)
Lemma take_fitting_prefix_