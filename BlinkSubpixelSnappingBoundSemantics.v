From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Blink Geometry Subpixel Snapping Maximum Error *)
Definition snap_subpixel_26_6 (raw : Z) : Z :=
  (raw + 32) / 64.

Theorem snapping_error_bounded : forall raw,
  -32 <= raw - 64 * snap_subpixel_26_6 raw <= 32.
Proof.
  intros raw.
  unfold snap_subpixel_26_6.
  assert (Hrem: 0 <= (raw + 32) mod 64 < 64) by (apply Z.mod_pos_bound; lia).
  assert (Heq: (raw + 32) = 64 * ((raw + 32) / 64) + (raw + 32) mod 64) by (apply Z.div_mod; lia).
  lia.
Qed.
