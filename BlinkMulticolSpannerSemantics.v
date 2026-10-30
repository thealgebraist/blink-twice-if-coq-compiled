(** * BlinkMulticolSpannerSemantics.v
    Formalization of Chromium Blink Multi-column Spanner Layout
    audited against CSS Multi-column Layout Module Level 1, Section 6.
*)

From Stdlib Require Import Arith.PeanoNat.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Core Data Structures *)

Definition LayoutUnit := nat.

Record MulticolConfig : Type := mkMulticolConfig {
  mc_col_width : LayoutUnit;
  mc_col_count : nat;        (* Used column-count N >= 1 *)
  mc_col_gap   : LayoutUnit
}.

Definition multicol_content_width (cfg : MulticolConfig) : LayoutUnit :=
  (mc_col_count cfg * mc_col_width cfg) +
  ((mc_col_count cfg - 1) * mc_col_gap cfg).

Inductive ChildKind : Type :=
  | RegularColumnChild : ChildKind
  | SpannerChild       : ChildKind.

Definition available_inline_size (cfg : MulticolConfig) (k : ChildKind) : LayoutUnit :=
  match k with
  | RegularColumnChild => mc_col_width cfg
  | SpannerChild       => multicol_content_width cfg
  end.

Inductive MulticolInputNode : Type :=
  | InflowBlock : LayoutUnit -> MulticolInputNode
  | SpannerBox  : LayoutUnit -> LayoutUnit -> MulticolInputNode
  | NestedBlock : list MulticolInputNode -> MulticolInputNode.

Inductive ColumnSpannerPath : Type :=
  | PathLeafAtSpanner : LayoutUnit -> LayoutUnit -> ColumnSpannerPath
  | PathStep          : nat -> ColumnSpannerPath -> ColumnSpannerPath.

Inductive LayoutPart : Type :=
  | ColumnRowPart : LayoutUnit -> LayoutPart
  | SpannerPart   : LayoutUnit -> LayoutUnit -> LayoutPart.

Record PositionedFragment : Type := mkFragment {
  frag_kind         : ChildKind;
  frag_block_offset : LayoutUnit;
  frag_inline_size  : LayoutUnit;
  frag_block_size   : LayoutUnit
}.

(** ** 2. Spanner Interruption and Column Balancing Semantics *)

Definition div_ceil (a b : nat) : nat :=
  match b with
  | 0 => 0
  | S b' => (a + b') / (S b')
  end.

Definition balanced_row_height (cfg : MulticolConfig) (raw_height : LayoutUnit) : LayoutUnit :=
  div_ceil raw_height (mc_col_count cfg).

Definition layout_single_part (cfg : MulticolConfig) (curr_y : LayoutUnit) (part : LayoutPart)
  : PositionedFragment * LayoutUnit :=
  match part with
  | ColumnRowPart raw_h =>
      let bal_h := balanced_row_height cfg raw_h in
      let frag := mkFragment RegularColumnChild curr_y (available_inline_size cfg RegularColumnChild) bal_h in
      (frag, curr_y + bal_h)
  | SpannerPart span_h margin_top =>
      let span_y := curr_y + margin_top in
      let span_w := available_inline_size cfg SpannerChild in
      let frag := mkFragment SpannerChild span_y span_w span_h in
      (frag, span_y + span_h)
  end.

Fixpoint layout_parts (cfg : MulticolConfig) (curr_y : LayoutUnit) (parts : list LayoutPart)
  : list PositionedFragment * LayoutUnit :=
  match parts with
  | [] => ([], curr_y)
  | p :: ps =>
      let (frag, next_y) := layout_single_part cfg curr_y p in
      let (frags, final_y) := layout_parts cfg next_y ps in
      (frag :: frags, final_y)
  end.

Inductive EvalMulticolLayout (cfg : MulticolConfig) :
  LayoutUnit -> list LayoutPart -> list PositionedFragment -> LayoutUnit -> Prop :=
  | Eval_Nil : forall y,
      EvalMulticolLayout cfg y [] [] y
  | Eval_ColumnRow : forall y raw_h ps frags final_y,
      let bal_h := balanced_row_height cfg raw_h in
      let frag := mkFragment RegularColumnChild y (available_inline_size cfg RegularColumnChild) bal_h in
      EvalMulticolLayout cfg (y + bal_h) ps frags final_y ->
      EvalMulticolLayout cfg y (ColumnRowPart raw_h :: ps) (frag :: frags) final_y
  | Eval_Spanner : forall y span_h margin_top ps frags final_y,
      let span_y := y + margin_top in
      let span_w := available_inline_size cfg SpannerChild in
      let frag := mkFragment SpannerChild span_y span_w span_h in
      EvalMulticolLayout cfg (span_y + span_h) ps frags final_y ->
      EvalMulticolLayout cfg y (SpannerPart span_h margin_top :: ps) (frag :: frags) final_y.

(** ** 3. Mathematical Invariants & Verification *)

(** Invariant 1: Spanner inline size matches the full content width of the multicol container *)
Theorem spanner_inline_size_full : forall cfg,
  available_inline_size cfg SpannerChild = multicol_content_width cfg.
Proof.
  intros cfg. reflexivity.
Qed.

(** Invariant 2: When column count is >= 1, spanner width is at least individual column width *)
Theorem spanner_width_ge_col_width : forall cfg,
  mc_col_count cfg >= 1 ->
  available_inline_size cfg SpannerChild >= available_inline_size cfg RegularColumnChild.
Proof.
  intros cfg Hcount.
  unfold available_inline_size, multicol_content_width.
  destruct (mc_col_count cfg) as [| c']; [lia |].
  simpl. lia.
Qed.

(** Invariant 3: Layout block offset advances monotonically *)
Theorem layout_parts_block_offset_monotonic : forall cfg parts y,
  snd (layout_parts cfg y parts) >= y.
Proof.
  intros cfg parts.
  induction parts as [| p ps IH]; intros y.
  - simpl. lia.
  - simpl.
    destruct p as [raw_h | span_h m].
    + simpl.
      specialize (IH (y + balanced_row_height cfg raw_h)).
      destruct (layout_parts cfg (y + balanced_row_height cfg raw_h) ps) as [frags final_y].
      simpl in *. lia.
    + simpl.
      specialize (IH (y + m + span_h)).
      destruct (layout_parts cfg (y + m + span_h) ps) as [frags final_y].
      simpl in *. lia.
Qed.

(** Invariant 4: Spanner offset following a column row is bounded below by the balanced height *)
Theorem spanner_after_row_offset_bound : forall cfg y raw_h span_h m,
  let '(frags, next_y) := layout_single_part cfg y (ColumnRowPart raw_h) in
  let '(span_frag, _) := layout_single_part cfg next_y (SpannerPart span_h m) in
  frag_block_offset span_frag >= y + balanced_row_height cfg raw_h + m.
Proof.
  intros cfg y raw_h span_h m.
  simpl. lia.
Qed.

(** Invariant 5: Functional evaluation satisfies relational specification *)
Theorem layout_parts_eval_sound : forall cfg parts y frags final_y,
  layout_parts cfg y parts = (frags, final_y) ->
  EvalMulticolLayout cfg y parts frags final_y.
Proof.
  intros cfg parts.
  induction parts as [| p ps IH]; intros y frags final_y Hlay.
  - simpl in Hlay.
    inversion Hlay; subst.
    apply Eval_Nil.
  - simpl in Hlay.
    destruct p as [raw_h | span_h m].
    + simpl in Hlay.
      destruct (layout_parts cfg (y + balanced_row_height cfg raw_h) ps) as [rest_frags rest_final_y] eqn:Hrec.
      inversion Hlay; subst.
      apply Eval_ColumnRow.
      apply (IH (y + balanced_row_height cfg raw_h) rest_frags final_y Hrec).
    + simpl in Hlay.
      destruct (layout_parts cfg (y + m + span_h) ps) as [rest_frags rest_final_y] eqn:Hrec.
      inversion Hlay; subst.
      apply Eval_Spanner.
      apply (IH (y + m + span_h) rest_frags final_y Hrec).
Qed.

