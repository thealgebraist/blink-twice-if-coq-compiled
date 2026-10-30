Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas Gradient Color Stop Monotonicity Semantics *)
(** HTML Canvas 2D §3: color stop offset clamped within [0, 1000] *)

Definition clamp_gradient_stop (offset : Z) : Z :=
  Z.max 0 (Z.min 1000 offset).

Theorem gradient_stop_bounded : forall o,
  0 <= clamp_gradient_stop o <= 1000.
Proof.
  intros o.
  unfold clamp_gradient_stop; lia.
Qed.
