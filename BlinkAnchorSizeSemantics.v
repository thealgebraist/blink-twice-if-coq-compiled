(******************************************************************************)
(* BlinkAnchorSizeSemantics.v                                                 *)
(* Sound Formal Specification for CSS Anchor Size Queries (anchor-size())     *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Anchor Positioning Level 1 (§4.2 The anchor-size() Function)    *)
(* 2. Blink AnchorEvaluatorImpl & AnchorQuery (`anchor_query.cc`)             *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Require Import BlinkPositionFallbackAndAnchor.
Open Scope Z_scope.

Inductive AnchorSizeAxis : Type :=
  | AxisWidth
  | AxisHeight
  | AxisTotal.

Definition evaluate_anchor_dimension (target : AnchorRect) (axis : AnchorSizeAxis) : Z :=
  match axis with
  | AxisWidth => sat_clamp (ar_w target)
  | AxisHeight => sat_clamp (ar_h target)
  | AxisTotal => sat_clamp (ar_w target + ar_h target)
  end.

Definition resolve_anchor_size_query (target : option AnchorRect)
                                    (axis : AnchorSizeAxis)
                                    (fallback_value : Z) : Z :=
  match target with
  | None => sat_clamp fallback_value
  | Some r => evaluate_anchor_dimension r axis
  end.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Lemma sat_clamp_nonneg : forall x : Z,
  0 <= x -> 0 <= sat_clamp x.
Proof.
  intros x Hx.
  unfold sat_clamp.
  destruct (Z.gtb_spec x kInt32Max); [unfold kInt32Max; lia |].
  destruct (Z.ltb_spec x kInt32Min); [unfold kInt32Min in *; lia | lia].
Qed.

Theorem anchor_size_nonneg :
  forall target axis fallback,
    (match target with Some r => 0 <= ar_w r /\ 0 <= ar_h r | None => 0 <= fallback end) ->
    0 <= resolve_anchor_size_query target axis fallback.
Proof.
  intros target axis fallback Hvalid.
  unfold resolve_anchor_size_query.
  destruct target as [r |].
  - destruct Hvalid as [Hw Hh].
    unfold evaluate_anchor_dimension.
    destruct axis; apply sat_clamp_nonneg; lia.
  - apply sat_clamp_nonneg. exact Hvalid.
Qed.

Theorem resolve_anchor_size_query_deterministic :
  forall target axis fallback r1 r2,
    r1 = resolve_anchor_size_query target axis fallback ->
    r2 = resolve_anchor_size_query target axis fallback ->
    r1 = r2.
Proof.
  intros target axis fallback r1 r2 H1 H2. subst. reflexivity.
Qed.
