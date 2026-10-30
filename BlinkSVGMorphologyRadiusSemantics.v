Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feMorphology Dilate and Erode Semantics *)
(** Filter Effects 1 §15: Morphology dilation and erosion *)

Definition morphology_dilate (v r : Z) : Z :=
  v + Z.max 0 r.

Definition morphology_erode (v r : Z) : Z :=
  v - Z.max 0 r.

Theorem dilate_expands : forall v r,
  0 <= r ->
  v <= morphology_dilate v r.
Proof.
  intros v r Hr.
  unfold morphology_dilate.
  assert (Z.max 0 r = r) by (apply Z.max_r; lia).
  rewrite H; lia.
Qed.

Theorem erode_shrinks : forall v r,
  0 <= r ->
  morphology_erode v r <= v.
Proof.
  intros v r Hr.
  unfold morphology_erode.
  assert (Z.max 0 r = r) by (apply Z.max_r; lia).
  rewrite H; lia.
Qed.

Theorem zero_radius_identity : forall v,
  morphology_dilate v 0 = v /\ morphology_erode v 0 = v.
Proof.
  intros v.
  unfold morphology_dilate, morphology_erode.
  split; lia.
Qed.
