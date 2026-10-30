Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas Dash Array Cycle Period Semantics *)
(** HTML Canvas 2D §4: dash pattern cycle period accumulation *)

Definition dash_period (d1 d2 : Z) : Z :=
  d1 + d2.

Theorem dash_period_positive : forall d1 d2,
  0 < d1 ->
  0 < d2 ->
  0 < dash_period d1 d2.
Proof.
  intros d1 d2 H1 H2.
  unfold dash_period; lia.
Qed.
