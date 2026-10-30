### 1. Baseline Rule: Chromium Blink Inline-Block vs. CSS 2.1 §10.8.1

According to **CSS 2.1 §10.8.1 (Leading and half-leading)**, the baseline of an `'inline-block'` element is determined by its `'overflow'` property and its in-flow content:

1. **Visible Overflow with In-Flow Content:** If the `'overflow'` property computes to `'visible'` and the element has one or more in-flow line boxes, the inline-block's baseline is the baseline of its **last** in-flow line box.
2. **Clipped/Scrolling Overflow or Empty Content:** If the `'overflow'` property computes to anything other than `'visible'` (e.g., `'hidden'`, `'scroll'`, `'auto'`, `'clip'`), OR if the element contains no in-flow line boxes, the baseline is the **bottom margin edge** (`margin_box_bottom`).

In Chromium's Blink engine (LayoutNG), this rule is implemented during box fragment generation (e.g., `NGBoxFragment::Baseline()` / `LogicalBoxFragment::FirstBaseline()` and `LastBaseline()`). When constructing an inline-block fragment, Blink checks `Style().IsOverflowVisible()`. If false, it suppresses inner line-box baseline propagation and synthesizes the baseline directly at the fragment's block-end margin edge.

---

### 2. Core Invariants

1. **Non-Visible Overflow Determinism (`overflow != visible`):** 
   For any inline-block element where `overflow != visible`, the computed baseline is strictly invariant with respect to its internal DOM subtree or in-flow line boxes. It resolves deterministically to `margin_box_bottom`. This guarantees that scrollable or clipped containers do not shift their external vertical alignment when internal content changes or scrolls.
2. **Empty Line-Box Fallback:** 
   When `overflow == visible` and the list of in-flow line boxes is empty (`nil`), the baseline cleanly degrades to `margin_box_bottom`, maintaining alignment continuity with non-visible overflow containers.
3. **Last Line-Box Dominance:** 
   When `overflow == visible` and in-flow line boxes exist, only the final line box in layout order dictates the baseline; preceding line boxes have zero effect on the external baseline metric.

---

### 3. Concrete Rocq/Coq Formalization

Below is the complete, self-contained formalization for `BlinkInlineBlockBaselineOverflowSemantics.v` with zero admits.

```coq
(** * BlinkInlineBlockBaselineOverflowSemantics.v
    Formal audit of Chromium Blink Inline-Block Baseline calculation
    against CSS 2.1 §10.8.1.
    Agent 232 Verification Artifact.
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Data Types & Layout Primitives *)

(** CSS 'overflow' computed values relevant to inline-block baseline *)
Inductive Overflow : Type :=
  | OverflowVisible
  | OverflowHidden
  | OverflowScroll
  | OverflowAuto
  | OverflowClip.

(** Decidable equality for Overflow *)
Definition overflow_eq_dec (o1 o2 : Overflow) : {o1 = o2} + {o1 <> o2}.
Proof.
  decide equality.
Defined.

(** Boolean check matching Blink's ComputedStyle::IsOverflowVisible() *)
Definition is_overflow_visible (o : Overflow) : bool :=
  match o with
  | OverflowVisible => true
  | _ => false
  end.

(** Representation of an in-flow line box within the inline-block *)
Record LineBox : Type := mkLineBox {
  line_box_baseline : Z
}.

(** Representation of an inline-block layout fragment *)
Record InlineBlockBox : Type := mkInlineBlockBox {
  ib_overflow : Overflow;
  ib_inflow_lines : list LineBox;
  ib_margin_box_bottom : Z
}.

(** ** 2. Baseline Semantics (CSS 2.1 §10.8.1 & Blink LayoutNG) *)

(** Helper to extract the last line box's baseline, falling back to a default value *)
Fixpoint last_line_baseline (lines : list LineBox) (default_val : Z) : Z :=
  match lines with
  | [] => default_val
  | [x] => line_box_baseline x
  | _ :: xs => last_line_baseline xs default_val
  end.

(** Specification of CSS 2.1 §10.8.1 inline-block baseline *)
Definition css21_inline_block_baseline (box : InlineBlockBox) : Z :=
  match ib_overflow box with
  | OverflowVisible =>
      match ib_inflow_lines box with
      | [] => ib_margin_box_bottom box
      | lines => last_line_baseline lines (ib_margin_box_bottom box)
      end
  | _ => ib_margin_box_bottom box
  end.

(** Blink LayoutNG implementation model *)
Definition blink_inline_block_baseline (box : InlineBlockBox) : Z :=
  if is_overflow_visible (ib_overflow box) then
    last_line_baseline (ib_inflow_lines box) (ib_margin_box_bottom box)
  else
    ib_margin_box_bottom box.

(** ** 3. Verification Theorems & Invariants *)

(** Theorem 1: Blink's implementation is strictly equivalent to CSS 2.1 §10.8.1 *)
Theorem blink_matches_css21 : forall (box : InlineBlockBox),
  blink_inline_block_baseline box = css21_inline_block_baseline box.
Proof.
  intros [overflow lines mb_bottom].
  unfold blink_inline_block_baseline, css21_inline_block_baseline.
  simpl.
  destruct overflow; simpl; try reflexivity.
  destruct lines; reflexivity.
Qed.

(** Theorem 2: Primary Audit Invariant — Non-visible overflow forces baseline 
    to margin_box_bottom regardless of in-flow line boxes. *)
Theorem non_visible_overflow_baseline_is_margin_bottom : forall (box : InlineBlockBox),
  ib_overflow box <> OverflowVisible ->
  blink_inline_block_baseline box = ib_margin_box_bottom box.
Proof.
  intros [overflow lines mb_bottom] H_non_vis.
  unfold blink_inline_block_baseline. simpl in *.
  destruct overflow; try reflexivity.
  exfalso. apply H_non_vis. reflexivity.
Qed.

(** Theorem 3: Deterministic Vertical Alignment under Content Mutation —
    When overflow != visible, mutating the internal line boxes does not alter the baseline. *)
Theorem non_visible_overflow_content_independence : forall (o : Overflow) (l1 l2 : list LineBox) (mb : Z),
  o <> OverflowVisible ->
  blink_inline_block_baseline (mkInlineBlockBox o l1 mb) =
  blink_inline_block_baseline (mkInlineBlockBox o l2 mb).
Proof.
  intros o l1 l2 mb H_non_vis.
  repeat rewrite non_visible_overflow_baseline_is_margin_bottom; simpl; auto.
Qed.

(** Theorem 4: Empty Line Box Fallback —
    If an inline-block has no in-flow line boxes, its baseline is always margin_box_bottom,
    independent of the overflow property. *)
Theorem empty_lines_baseline_is_margin_bottom : forall (o : Overflow) (mb : Z),
  blink_inline_block_baseline (mkInlineBlockBox o [] mb) = mb.
Proof.
  intros o mb.
  unfold blink_inline_block_baseline. simpl.
  destruct (is_overflow_visible o); reflexivity.
Qed.

(** Lemma: Connection between last_line_baseline and Coq's standard List.last *)
Lemma last_line_baseline_correct : forall (lines : list LineBox) (default_lb : LineBox),
  lines <> [] ->
  last_line_baseline lines (line_box_baseline default_lb) =
  line_box_baseline (last lines default_lb).
Proof.
  induction lines as [| x xs IH]; intros default_lb H_non_empty.
  - exfalso. apply H_non_empty. reflexivity.
  - simpl. destruct xs as [| y ys].
    + reflexivity.
    + apply IH. discriminate.
Qed.

(** Theorem 5: Visible Overflow with Non-Empty Lines —
    When overflow is visible and lines exist, the baseline is strictly the last line's baseline. *)
Theorem visible_non_empty_uses_last_line : forall (lines : list LineBox) (mb : Z) (dummy : LineBox),
  lines <> [] ->
  blink_inline_block_baseline (mkInlineBlockBox OverflowVisible lines mb) =
  line_box_baseline (last lines dummy).
Proof.
  intros lines mb dummy H_non_empty.
  unfold blink_inline_block_baseline. simpl.
  induction lines as [| x xs IH].
  - exfalso. apply H_non_empty. reflexivity.
  - simpl. destruct xs as [| y ys].
    + reflexivity.
    + apply IH. discriminate.
Qed.
```