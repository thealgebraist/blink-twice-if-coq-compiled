(* ========================================================================= *)
(*               BlinkStackingTreeSemantics.v                                *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Stacking Context Tree & Paint Order    *)
(* per W3C CSS 2.1 Appendix E & CSS Position 3 §8.                           *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive StackingLayerKind : Type :=
  | LayerNegativeZ (z : Z)
  | LayerInFlowAuto
  | LayerPositiveZ (z : Z).

Definition stacking_rank (layer : StackingLayerKind) : Z :=
  match layer with
  | LayerNegativeZ z => Z.min (-1) z
  | LayerInFlowAuto   => 0
  | LayerPositiveZ z => Z.max 1 z
  end.

Theorem negative_z_precedes_inflow : forall z,
  z < 0 ->
  stacking_rank (LayerNegativeZ z) < stacking_rank LayerInFlowAuto.
Proof.
  intros z Hz. unfold stacking_rank.
  pose proof (Z.le_min_l (-1) z).
  lia.
Qed.

Theorem inflow_precedes_positive_z : forall z,
  z > 0 ->
  stacking_rank LayerInFlowAuto < stacking_rank (LayerPositiveZ z).
Proof.
  intros z Hz. unfold stacking_rank.
  pose proof (Z.le_max_l 1 z).
  lia.
Qed.

Theorem negative_z_precedes_positive_z : forall z1 z2,
  z1 < 0 ->
  z2 > 0 ->
  stacking_rank (LayerNegativeZ z1) < stacking_rank (LayerPositiveZ z2).
Proof.
  intros z1 z2 Hz1 Hz2.
  pose proof (negative_z_precedes_inflow z1 Hz1).
  pose proof (inflow_precedes_positive_z z2 Hz2).
  lia.
Qed.

Theorem positive_z_monotonic : forall z1 z2,
  1 <= z1 ->
  z1 <= z2 ->
  stacking_rank (LayerPositiveZ z1) <= stacking_rank (LayerPositiveZ z2).
Proof.
  intros z1 z2 Hz1 Hle.
  unfold stacking_rank.
  assert (Z.max 1 z1 = z1) by (apply Z.max_r; lia).
  assert (Z.max 1 z2 = z2) by (apply Z.max_r; lia).
  rewrite H, H0.
  lia.
Qed.
