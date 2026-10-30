Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Input Step Quantization Semantics *)
(** HTML Standard §4.10.5.2: step quantization exactness *)

Definition quantize_step (val min_val step : Z) : Z :=
  if step <=? 0 then val
  else min_val + ((val - min_val) / step) * step.

Theorem quantize_exact_step : forall m s k,
  0 < s ->
  0 <= k ->
  quantize_step (m + k * s) m s = m + k * s.
Proof.
  intros m s k Hs Hk.
  unfold quantize_step.
  destruct (s <=? 0) eqn:Heq.
  - apply Z.leb_le in Heq; lia.
  - replace (m + k * s - m) with (k * s) by ring.
    rewrite Z.div_mul by lia.
    reflexivity.
Qed.
