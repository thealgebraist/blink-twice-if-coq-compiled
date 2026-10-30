Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Reversing Transition Factor Semantics *)
(** CSS Transitions 1 §3.2: reversing factor bounding *)

Definition clamp_reversing_factor (factor : Z) : Z :=
  Z.max 0 (Z.min 1000 factor).

Theorem reversing_factor_bounded : forall f,
  0 <= clamp_reversing_factor f <= 1000.
Proof.
  intros f.
  unfold clamp_reversing_factor.
  lia.
Qed.
