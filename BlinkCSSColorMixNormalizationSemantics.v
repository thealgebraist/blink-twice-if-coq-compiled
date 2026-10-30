Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS color-mix() Normalization Semantics *)
(** CSS Color 5 §3: color-mix() percentage weights normalize to 100% *)

Definition normalize_color_mix_weights (p1 p2 : Z) : (Z * Z) :=
  (p1, 100 - p1).

Theorem color_mix_weights_sum_to_100 : forall p1 p2,
  fst (normalize_color_mix_weights p1 p2) + snd (normalize_color_mix_weights p1 p2) = 100.
Proof.
  intros p1 p2.
  unfold normalize_color_mix_weights.
  cbn [fst snd].
  lia.
Qed.
