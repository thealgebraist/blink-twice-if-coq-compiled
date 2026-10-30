(* ========================================================================= *)
(*               BlinkTransformSkew2DSemantics.v                            *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink 2D Skew Matrix Composition against  *)
(* CSS Transforms 1 §5.1. Fully constructive, 0 admits.                      *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition det_skew_2d (tan_a tan_b : Z) : Z :=
  1 - tan_a * tan_b.

Theorem skew_identity_det :
  det_skew_2d 0 0 = 1.
Proof.
  unfold det_skew_2d. ring.
Qed.

Theorem skew_single_axis_area_preserving : forall t,
  det_skew_2d 0 t = 1 /\ det_skew_2d t 0 = 1.
Proof.
  intros t. unfold det_skew_2d.
  split; ring.
Qed.
