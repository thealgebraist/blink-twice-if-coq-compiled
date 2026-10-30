Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas Pattern Repeat Wrapping Semantics *)
(** HTML Canvas 2D §3: modulo coordinate wrapping *)

Definition wrap_pattern_coord (coord dim : Z) : Z :=
  if dim <=? 0 then 0
  else coord mod dim.

Theorem pattern_wrap_bounded : forall c d,
  0 < d ->
  0 <= wrap_pattern_coord c d < d.
Proof.
  intros c d Hd.
  unfold wrap_pattern_coord.
  destruct (d <=? 0) eqn:Heq.
  - apply Z.leb_le in Heq; lia.
  - apply Z.mod_pos_bound; exact Hd.
Qed.
