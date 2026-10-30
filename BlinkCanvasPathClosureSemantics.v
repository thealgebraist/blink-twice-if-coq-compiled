Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Path2D Subpath Closure Semantics *)
(** HTML Canvas 2D §4: closePath connects to initial subpath coordinates *)

Definition close_subpath (cur_x cur_y init_x init_y : Z) : (Z * Z) :=
  (init_x, init_y).

Theorem close_subpath_connects_to_start : forall cx cy ix iy,
  close_subpath cx cy ix iy = (ix, iy).
Proof.
  intros cx cy ix iy; reflexivity.
Qed.
