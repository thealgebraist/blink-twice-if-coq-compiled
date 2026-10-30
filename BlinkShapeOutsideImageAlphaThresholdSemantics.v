Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Shape Outside Image Alpha Threshold Semantics *)
(** CSS Shapes 1 §3.3: shape-image-threshold alpha cutoff *)

Definition is_pixel_opaque (alpha threshold : Z) : bool :=
  threshold <=? alpha.

Theorem opacity_monotonic : forall alpha1 alpha2 threshold,
  alpha1 <= alpha2 ->
  is_pixel_opaque alpha1 threshold = true ->
  is_pixel_opaque alpha2 threshold = true.
Proof.
  intros alpha1 alpha2 threshold Hle Hop.
  unfold is_pixel_opaque in *.
  apply Z.leb_le in Hop.
  apply Z.leb_le.
  lia.
Qed.
