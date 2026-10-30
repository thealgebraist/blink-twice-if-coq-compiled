(** * BlinkOutOfFlowStaticPositionSemantics.v
    Formalization of Chromium Blink LayoutNG Out-Of-Flow (OOF) Static Position
    vs. CSS Positioned Layout Module Level 3 §5.
*)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import micromega.Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Definition LayoutUnit := Z.

Record LogicalOffset : Type := mkLogicalOffset {
  inline_offset : LayoutUnit;
  block_offset  : LayoutUnit
}.

Inductive InlineEdge : Type :=
  | kInlineStart
  | kInlineCenter
  | kInlineEnd.

Inductive BlockEdge : Type :=
  | kBlockStart
  | kBlockCenter
  | kBlockEnd.

Record LogicalStaticPosition : Type := mkLogicalStaticPosition {
  offset      : LogicalOffset;
  inline_edge : InlineEdge;
  block_edge  : BlockEdge
}.

Inductive StaticEdge1D : Type :=
  | EdgeStart
  | EdgeCenter
  | EdgeEnd.

Definition inline_to_1d (e : InlineEdge) : StaticEdge1D :=
  match e with
  | kInlineStart  => EdgeStart
  | kInlineCenter => EdgeCenter
  | kInlineEnd    => EdgeEnd
  end.

Definition block_to_1d (e : BlockEdge) : StaticEdge1D :=
  match e with
  | kBlockStart  => EdgeStart
  | kBlockCenter => EdgeCenter
  | kBlockEnd    => EdgeEnd
  end.

Inductive InsetValue : Type :=
  | InsetAuto
  | InsetFixed (v : LayoutUnit).

(** ** 2. Static Position Discovery and Propagation *)

Definition compute_local_block_static_position
  (content_box_inline_start : LayoutUnit)
  (bfc_block_offset : LayoutUnit)
  (margin_strut_sum : LayoutUnit) : LogicalStaticPosition :=
  mkLogicalStaticPosition
    (mkLogicalOffset content_box_inline_start (bfc_block_offset + margin_strut_sum))
    kInlineStart
    kBlockStart.

Fixpoint propagate_static_position
  (st : LogicalStaticPosition)
  (ancestor_offsets : list LogicalOffset) : LogicalStaticPosition :=
  match ancestor_offsets with
  | [] => st
  | o :: rest =>
      let updated_offset := mkLogicalOffset
        (inline_offset (offset st) + inline_offset o)
        (block_offset (offset st) + block_offset o) in
      propagate_static_position
        (mkLogicalStaticPosition updated_offset (inline_edge st) (block_edge st))
        rest
  end.

(** ** 3. 1D Inset Resolution with Static Position *)

Definition resolve_1d_insets
  (edge : StaticEdge1D)
  (p_static : LayoutUnit)
  (cb_size : LayoutUnit)
  (s_margin : LayoutUnit)
  (inset_start_spec : InsetValue)
  (inset_end_spec : InsetValue) : (LayoutUnit * LayoutUnit) :=
  match inset_start_spec, inset_end_spec with
  | InsetAuto, InsetAuto =>
      match edge with
      | EdgeStart =>
          let start_val := p_static in
          let end_val := cb_size - p_static - s_margin in
          (start_val, end_val)
      | EdgeCenter =>
          let start_val := p_static - s_margin / 2 in
          let end_val := cb_size - start_val - s_margin in
          (start_val, end_val)
      | EdgeEnd =>
          let end_val := cb_size - p_static in
          let start_val := p_static - s_margin in
          (start_val, end_val)
      end
  | InsetFixed v_start, InsetAuto =>
      (v_start, cb_size - v_start - s_margin)
  | InsetAuto, InsetFixed v_end =>
      (cb_size - v_end - s_margin, v_end)
  | InsetFixed v_start, InsetFixed v_end =>
      (v_start, v_end)
  end.

(** ** 4. Mathematical Invariants & Verification *)

(** Invariant 1: 1D Positioned Constraint Equation Exact Satisfaction *)
Theorem constraint_equation_satisfied_auto :
  forall edge p_static cb_size s_margin,
    let '(i_start, i_end) :=
      resolve_1d_insets edge p_static cb_size s_margin InsetAuto InsetAuto in
    i_start + s_margin + i_end = cb_size.
Proof.
  intros edge p_static cb_size s_margin.
  unfold resolve_1d_insets.
  destruct edge; lia.
Qed.

(** Invariant 2: Start Edge Inset Non-Negativity when P_static >= 0 *)
Theorem start_edge_nonneg :
  forall p_static cb_size s_margin,
    0 <= p_static ->
    let '(i_start, _) :=
      resolve_1d_insets EdgeStart p_static cb_size s_margin InsetAuto InsetAuto in
    0 <= i_start.
Proof.
  intros p_static cb_size s_margin Hp.
  unfold resolve_1d_insets.
  simpl. lia.
Qed.

(** Invariant 3: Bounded Insets when Margin Box Fits within Containing Block *)
Theorem start_edge_bounds_containment :
  forall p_static cb_size s_margin,
    0 <= p_static ->
    p_static + s_margin <= cb_size ->
    let '(i_start, i_end) :=
      resolve_1d_insets EdgeStart p_static cb_size s_margin InsetAuto InsetAuto in
    0 <= i_start /\ 0 <= i_end.
Proof.
  intros p_static cb_size s_margin Hp0 Hfit.
  unfold resolve_1d_insets.
  simpl. lia.
Qed.

(** Invariant 4: End Edge Alignment Equivalence *)
Theorem end_edge_alignment_exact :
  forall p_static cb_size s_margin,
    let '(i_start, i_end) :=
      resolve_1d_insets EdgeEnd p_static cb_size s_margin InsetAuto InsetAuto in
    i_start + s_margin = p_static.
Proof.
  intros p_static cb_size s_margin.
  unfold resolve_1d_insets.
  simpl. lia.
Qed.

(** Invariant 5: Offset Propagation Additivity across Ancestors *)
Theorem propagate_static_position_app :
  forall st l1 l2,
    offset (propagate_static_position st (l1 ++ l2)) =
    offset (propagate_static_position (propagate_static_position st l1) l2).
Proof.
  intros st l1.
  revert st.
  induction l1 as [| o os IH]; intros st l2.
  - simpl. reflexivity.
  - simpl.
    apply IH.
Qed.

