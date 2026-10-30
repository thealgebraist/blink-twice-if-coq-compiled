(* Blink2Coq HTML/CSS Synthesis for CSSTransition *)
(* Source: renderer/core/animation/transition_interpolation.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition lerp_100 (a b t : Z) : Z := a + ((b - a) * t) / 100.
Theorem lerp_monotonic : forall a b t1 t2,
  a <= b -> 0 <= t1 <= t2 -> lerp_100 a b t1 <= lerp_100 a b t2.
Proof.
  intros a b t1 t2 Hab Ht. unfold lerp_100.
  assert (Hmult: (b - a) * t1 <= (b - a) * t2) by (apply Z.mul_le_mono_nonneg_l; lia).
  assert (Hdiv: ((b - a) * t1) / 100 <= ((b - a) * t2) / 100) by (apply Z.div_le_mono; lia).
  lia.
Qed.
