# Formal Verification Research Report: Atomic Inline Fragment Bounds and Baseline Alignment in Chromium Blink

**Agent:** Formal Verification Agent 683  
**Specialization:** W3C/WHATWG Layout Rules (Block, Inline, Flexbox) in Chromium Blink  
**Topic:** Atomic inline fragment bounds and baseline alignment  
**Chromium Source:** `third_party/blink/renderer/core/layout/inline/inline_box_state.cc`  
**Specification:** CSS 2.1 §10.8.1 (Leading and half-leading) & CSS Inline Layout Module Level 3  
**Formal Theory Target:** `BlinkInlineBoxAtomicFragmentBoundsSemantics.v`  
**Mathematical Property:** $\text{atomic\_baseline}(\text{has\_line}, \text{line\_b}, \text{box\_h}) = \text{if } \text{has\_line} \text{ then } \text{line\_b} \text{ else } \text{box\_h}$

---

## 1. Normative W3C Specification Requirements

In the CSS visual formatting model, **atomic inline-level boxes** (such as `inline-block`, `inline-table`, `inline-flex`, `inline-grid`, and replaced inline elements) participate in an inline formatting context as a single opaque box that cannot be split across lines. Their vertical positioning within a line box is governed by their baseline synthesis rules and margin box bounds.

### 1.1 CSS 2.1 §10.8 Line Height Calculations: the `line-height` and `vertical-align` properties
According to **CSS 2.1 §10.8.1**:
> *"The baseline of an 'inline-block' is the baseline of its last line box in the normal flow, unless it has either no in-flow line boxes or if its 'overflow' property has a computed value other than 'visible', in which case the baseline is the bottom margin edge."*

### 1.2 CSS Inline Layout Module Level 3 (§4.1 & §5)
The modern CSS Inline Layout specification generalizes this behavior across layout modes:
1. **Margin Box Bounds as Layout Bounds:** For atomic inlines, the layout bounds (the ascent and descent metrics contributed to the parent line box) are derived from the box's margin edges. Specifically, the total height of the atomic inline is $H_{\text{box}} = \text{ascent} + \text{descent}$, where $\text{ascent}$ is the distance from the top margin edge to the synthesized baseline, and $\text{descent}$ is the distance from the synthesized baseline to the bottom margin edge.
2. **Baseline Synthesis Fallback:** If an atomic inline box attempts to export an alphabetic baseline from its internal formatting context (e.g., the last in-flow line box of an `inline-block`, or the first/last baseline of an `inline-flex` container) and succeeds (and `overflow` allows baseline propagation), its baseline offset measured from the top margin edge is $B_{\text{line}}$. If no such internal baseline exists (or is suppressed by non-visible `overflow`), the baseline falls back to the bottom margin edge: $B_{\text{fallback}} = H_{\text{box}}$.
3. **Metric Decomposition:** Given a total margin-box height $H_{\text{box}} \ge 0$ and a baseline offset $B$ measured downward from the top margin edge:
   $$\text{ascent} = B, \quad \text{descent} = H_{\text{box}} - B$$
   When the fallback is triggered ($B = H_{\text{box}}$), the atomic inline resolves to $\text{ascent} = H_{\text{box}}$ and $\text{descent} = 0$.

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink's LayoutNG architecture, inline formatting context construction and line box metric accumulation are managed by `InlineBoxState` and `InlineLayoutStateStack` inside `third_party/blink/renderer/core/layout/inline/inline_box_state.cc`.

### 2.1 Execution Flow in `inline_box_state.cc`
When an atomic inline finishes its internal layout via its respective block/flex/grid layout algorithm, it produces a `PhysicalBoxFragment` wrapped in a `LogicalLineItem`. During line box construction (`InlineLayoutAlgorithm::CreateLine`), the state machine processes atomic inline items via `InlineLayoutStateStack::OnOpenTag` / ` InlineBoxState::AccumulateUsedFonts` and `InlineBoxState::ComputeTextMetrics` / atomic inline handling:

```cpp
// Conceptual representation of Blink's metric extraction for atomic inlines
// in third_party/blink/renderer/core/layout/inline/inline_box_state.cc
// and LogicalLineItem / BoxFragmentBaseline resolution:

FontHeight ComputeAtomicInlineMetrics(const PhysicalBoxFragment& fragment,
                                      const LineBoxStrut& margins,
                                      FontBaseline baseline_type) {
  LayoutUnit box_height = fragment.Size().height + margins.LineOver() + margins.LineUnder();
  
  // Query the fragment for its synthesized baseline (e.g. last in-flow line box).
  // Returns std::nullopt if the box has no in-flow line boxes or overflow != visible.
  std::optional<LayoutUnit> line_baseline = fragment.Baseline(baseline_type);
  
  LayoutUnit baseline_offset = line_baseline.has_value()
                                   ? (*line_baseline + margins.LineOver())
                                   : box_height;
                                   
  LayoutUnit ascent = baseline_offset;
  LayoutUnit descent = box_height - ascent;
  return FontHeight(ascent, descent);
}
```

### 2.2 Core Implementation Invariants
1. **Metric Conservation (`FontHeight::LineHeight()`):** Regardless of whether an internal line box baseline is present, the sum of the resulting `FontHeight.ascent` and `FontHeight.descent` must equal the exact total margin-box height (`box_height`) of the atomic inline fragment:
   $$\text{ascent} + \text{descent} = \text{box\_h}$$
2. **Zero Descent on Fallback:** When `has_line` is `false`, `ascent` equals `box_height` and `descent` is identically `0`. The entire atomic inline box sits on top of the parent line box's baseline.
3. **Non-Negative Bounds Preservation:** If the internal baseline `line_b` is geometrically bounded within the margin box ($0 \le \text{line\_b} \le \text{box\_h}$), then both `ascent` and `descent` are guaranteed to be non-negative ($\text{ascent} \ge 0 \land \text{descent} \ge 0$).
4. **Line Box Enclosure (`FontHeight::Unite`):** When an atomic inline with `vertical-align: baseline` is united into the enclosing `InlineBoxState::metrics` via `metrics.Unite(atomic_metrics)`, the parent line box's total height is at least the height of the atomic inline ($\text{parent\_ascent}' + \text{parent\_descent}' \ge \text{box\_h}$).

---

## 3. Formal Specification in Rocq/Coq

Below is the self-contained formalization of `BlinkInlineBoxAtomicFragmentBoundsSemantics.v`. It models `LayoutUnit` coordinates in $\mathbb{Z}$, defines the core mathematical property `atomic_baseline`, constructs `FontHeight` metric structures, and models Blink's `InlineBoxState` metric unification.

```coq
(** * BlinkInlineBoxAtomicFragmentBoundsSemantics.v
    Formal verification of W3C CSS 2.1 §10.8.1 and Chromium Blink's
    atomic inline fragment bounds and baseline alignment semantics
    (third_party/blink/renderer/core/layout/inline/inline_box_state.cc). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(** ** 1. Basic Types and Mathematical Property *)

(** In Blink, LayoutUnit is a fixed-point arithmetic type. We model it over Z. *)
Definition LayoutUnit := Z.

(** Core Mathematical Property:
    atomic_baseline(has_line, line_b, box_h) = if has_line then line_b else box_h.
    - [has_line]: true iff the atomic inline has an usable in-flow line baseline
                  (and overflow is visible).
    - [line_b]:   the baseline offset from the top margin edge when [has_line] is true.
    - [box_h]:    the total margin-box height of the atomic inline fragment. *)
Definition atomic_baseline (has_line : bool) (line_b box_h : LayoutUnit) : LayoutUnit :=
  if has_line then line_b else box_h.

(** ** 2. Blink FontHeight (LineBoxStrut) Metric Representation *)

(** Represents Blink's [FontHeight] struct in inline_box_state.h, decomposed
    into distance above the baseline ([ascent]) and below the baseline ([descent]). *)
Record FontHeight : Type := mkFontHeight {
  ascent  : LayoutUnit;
  descent : LayoutUnit
}.

(** Total height occupied by a [FontHeight] strut. *)
Definition font_height_total (fh : FontHeight) : LayoutUnit :=
  ascent fh + descent fh.

(** Computes the [FontHeight] of an atomic inline fragment given its parameters. *)
Definition compute_atomic_metrics (has_line : bool) (line_b box_h : LayoutUnit) : FontHeight :=
  let b := atomic_baseline has_line line_b box_h in
  mkFontHeight b (box_h - b).

(** Corresponds to [FontHeight::Unite] in Blink's font_height.cc:
    expands the current line box metrics to enclose another [FontHeight]. *)
Definition font_height_unite (a b : FontHeight) : FontHeight :=
  mkFontHeight (Z.max (ascent a) (ascent b)) (Z.max (descent a) (descent b)).

(** ** 3. Atomic Inline Fragment & InlineBoxState Models *)

(** Model of an atomic inline item processed by [InlineBoxState]. *)
Record AtomicInlineFragment : Type := mkAtomicFragment {
  frag_has_line      : bool;
  frag_line_baseline : LayoutUnit;
  frag_margin_over   : LayoutUnit;
  frag_border_box_h  : LayoutUnit;
  frag_margin_under  : LayoutUnit;
  frag_baseline_shift : LayoutUnit (** Offset introduced by vertical-align *)
}.

(** Total margin-box height of an atomic inline fragment. *)
Definition fragment_box_height (f : AtomicInlineFragment) : LayoutUnit :=
  frag_margin_over f + frag_border_box_h f + frag_margin_under f.

(** Internal baseline translated into margin-box coordinates. *)
Definition fragment_adjusted_line_baseline (f : AtomicInlineFragment) : LayoutUnit :=
  frag_margin_over f + frag_line_baseline f.

(** Computes the unshifted [FontHeight] metrics for an [AtomicInlineFragment]. *)
Definition fragment_metrics (f : AtomicInlineFragment) : FontHeight :=
  compute_atomic_metrics
    (frag_has_line f)
    (fragment_adjusted_line_baseline f)
    (fragment_box_height f).

(** Applies Blink's [Move] operation for baseline shift (vertical-align). *)
Definition apply_baseline_shift (fh : FontHeight) (shift : LayoutUnit) : FontHeight :=
  mkFontHeight (ascent fh - shift) (descent fh + shift).

(** Well-formedness predicate for an [AtomicInlineFragment]:
    - Border-box height is non-negative.
    - Margin-box height is non-negative.
    - If [frag_has_line] is true, the internal line baseline lies within the
      border box [0 <= frag_line_baseline <= frag_border_box_h] and margins
      are non-negative (or more generally, adjusted baseline is within [0, box_h]). *)
Definition well_formed_fragment (f : AtomicInlineFragment) : Prop :=
  0 <= fragment_box_height f /\
  (frag_has_line f = true ->
   0 <= fragment_adjusted_line_baseline f <= fragment_box_height f).

(** Accumulation of a list of atomic inline fragments into an initial [FontHeight]
    (representing the text strut of an [InlineBoxState]). *)
Definition accumulate_atomic_fragments
  (init_strut : FontHeight) (frags : list AtomicInlineFragment) : FontHeight :=
  fold_left
    (fun acc f =>
       font_height_unite acc (apply_baseline_shift (fragment_metrics f) (frag_baseline_shift f)))
    frags
    init_strut.
```

---

## 4. Concrete Theorems and Complete Proofs

All theorems below are proven using standard Rocq/Coq libraries (`ZArith`, `Lia`, `Bool`, `List`) with **zero admits**.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: Direct specification of CSS 2.1 §10.8.1 fallback rule.
    When an atomic inline has no in-flow line box ([has_line = false]),
    its baseline falls exactly on its bottom margin edge ([box_h]),
    yielding an ascent of [box_h] and a descent of [0]. *)
Theorem css21_10_8_1_no_line_fallback :
  forall (line_b box_h : LayoutUnit),
    atomic_baseline false line_b box_h = box_h /\
    ascent (compute_atomic_metrics false line_b box_h) = box_h /\
    descent (compute_atomic_metrics false line_b box_h) = 0.
Proof.
  intros line_b box_h.
  unfold compute_atomic_metrics, atomic_baseline; simpl.
  lia.
Qed.

(** Theorem 2: Direct specification of CSS 2.1 §10.8.1 in-flow line rule.
    When an atomic inline has an in-flow line box ([has_line = true]),
    its baseline is [line_b], ascent is [line_b], and descent is [box_h - line_b]. *)
Theorem css21_10_8_1_in_flow_line :
  forall (line_b box_h : LayoutUnit),
    atomic_baseline true line_b box_h = line_b /\
    ascent (compute_atomic_metrics true line_b box_h) = line_b /\
    descent (compute_atomic_metrics true line_b box_h) = box_h - line_b.
Proof.
  intros line_b box_h.
  unfold compute_atomic_metrics, atomic_baseline; simpl.
  lia.
Qed.

(** Theorem 3: Metric Conservation Invariant.
    For any boolean [has_line], internal baseline [line_b], and box height [box_h],
    the total height of the synthesized [FontHeight] equals [box_h]. *)
Theorem atomic_metrics_height_conservation :
  forall (has_line : bool) (line_b box_h : LayoutUnit),