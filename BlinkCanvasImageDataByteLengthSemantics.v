Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas ImageData Buffer Length Semantics *)
(** HTML Canvas 2D §11: buffer byte length = 4 * w * h identity *)

Definition compute_imagedata_bytes (w h : Z) : Z :=
  4 * w * h.

Theorem imagedata_bytes_nonneg : forall w h,
  0 <= w ->
  0 <= h ->
  0 <= compute_imagedata_bytes w h.
Proof.
  intros w h Hw Hh.
  unfold compute_imagedata_bytes; lia.
Qed.
