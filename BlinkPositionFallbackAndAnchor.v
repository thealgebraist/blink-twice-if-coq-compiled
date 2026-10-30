(******************************************************************************)
(* BlinkPositionFallbackAndAnchor.v                                           *)
(* Sound Formal Big-Step Operational Semantics for CSS Anchor Positioning      *)
(* & @position-try Fallback Resolution (W3C CSS Anchor Positioning 1)         *)
(*                                                                            *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Anchor Positioning Level 1 (§3 Determining the Anchor,         *)
(*    §4 The anchor() and anchor-size() Functions, §6 Position Fallback)      *)
(* 2. Blink AnchorEvaluatorImpl (`anchor_evaluator_impl.cc`) &                *)
(*    OutOfFlowLayoutPart fallback candidate resolution                       *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Require Import BlinkPhysicalFragment.
Require Import BlinkOutOfFlowSemantics.
Import ListNotations.
Open Scope Z_scope.

Inductive AnchorSide : Type :=
  | AnchorTop
  | AnchorLeft
  | AnchorBottom
  | AnchorRight.

Record AnchorRect := mkAnchorRect {
  ar_x : Z;
  ar_y : Z;
  ar_w : Z;
  ar_h : Z
}.

Definition evaluate_anchor_side (target : AnchorRect) (side : AnchorSide) : Z :=
  match side with
  | AnchorTop => ar_y target
  | AnchorLeft => ar_x target
  | AnchorBottom => sat_clamp (ar_y target + ar_h target)
  | AnchorRight => sat_clamp (ar_x target + ar_w target)
  end.

Record PositionTryOption := mkPositionTryOption {
  pto_top : InsetValue;
  pto_left : InsetValue;
  pto_bottom : InsetValue;
  pto_right : InsetValue
}.

Definition fits_in_viewport (box : PhysicalBox) (vp_w vp_h : Z) : bool :=
  (0 <=? box_x box) && (sat_clamp (box_x box + box_w box) <=? vp_w) &&
  (0 <=? box_y box) && (sat_clamp (box_y box + box_h box) <=? vp_h).

Fixpoint resolve_position_try (candidates : list PositionTryOption)
                              (cb : ContainingBlock) (sx sy : Z)
                              (w h : Z) (vp_w vp_h : Z)
                              (fallback_insets : PositionedInsets) : PhysicalBox :=
  match candidates with
  | [] =>
      (* Default fallback *)
      resolve_out_of_flow_box cb sx sy fallback_insets w h
  | opt :: rest =>
      let insets := mkPositionedInsets (pto_left opt) (pto_right opt) (pto_top opt) (pto_bottom opt) in
      let candidate_box := resolve_out_of_flow_box cb sx sy insets w h in
      if fits_in_viewport candidate_box vp_w vp_h then
        candidate_box
      else
        resolve_position_try rest cb sx sy w h vp_w vp_h fallback_insets
  end.

(******************************************************************************)
(* SOUNDNESS THEOREMS                                                         *)
(******************************************************************************)

Theorem position_try_deterministic :
  forall cands cb sx sy w h vp_w vp_h def_insets b1 b2,
    b1 = resolve_position_try cands cb sx sy w h vp_w vp_h def_insets ->
    b2 = resolve_position_try cands cb sx sy w h vp_w vp_h def_insets ->
    b1 = b2.
Proof.
  intros cands cb sx sy w h vp_w vp_h def_insets b1 b2 H1 H2.
  subst. reflexivity.
Qed.

Theorem position_try_nonneg_dimensions :
  forall cands cb sx sy w h vp_w vp_h def_insets,
    0 <= w -> 0 <= h ->
    let b := resolve_position_try cands cb sx sy w h vp_w vp_h def_insets in
    0 <= box_w b /\ 0 <= box_h b.
Proof.
  induction cands as [| opt rest IH]; intros cb sx sy w h vp_w vp_h def_insets Hw Hh.
  - simpl. apply out_of_flow_fragment_size_nonneg; assumption.
  - simpl.
    destruct (fits_in_viewport (resolve_out_of_flow_box cb sx sy
       {|
         inset_left := pto_left opt;
         inset_right := pto_right opt;
         inset_top := pto_top opt;
         inset_bottom := pto_bottom opt
       |} w h) vp_w vp_h).
    + apply out_of_flow_fragment_size_nonneg; assumption.
    + apply IH; assumption.
Qed.
