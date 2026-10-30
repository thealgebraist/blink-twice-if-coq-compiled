Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Paint Worklet Execution Semantics *)
(** CSS Painting 1 §3: paint worklet alpha output scaling *)

Definition paint_worklet_alpha_isolation (input_alpha worklet_multiplier : Z) : Z :=
  (input_alpha * worklet_multiplier) / 100.

Theorem paint_worklet_alpha_nonneg : forall a m,
  0 <= a ->
  0 <= m ->
  0 <= paint_worklet_alpha_isolation a m.
Proof.
  intros a m Ha Hm.
  unfold paint_worklet_alpha_isolation.
  apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia | lia].
Qed.
