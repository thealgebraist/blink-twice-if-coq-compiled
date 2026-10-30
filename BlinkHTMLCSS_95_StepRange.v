(* Blink2Coq HTML/CSS Synthesis for StepRange *)
(* Source: renderer/core/html/forms/step_range.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition stepped_value (min_val step k : Z) : Z := min_val + k * step.
Theorem stepped_value_monotonic : forall min_val step k,
  0 < step -> 0 <= k -> min_val <= stepped_value min_val step k.
Proof.
  intros min_val step k Hstep Hk. unfold stepped_value.
  assert (0 <= k * step) by (apply Z.mul_nonneg_nonneg; lia).
  lia.
Qed.
