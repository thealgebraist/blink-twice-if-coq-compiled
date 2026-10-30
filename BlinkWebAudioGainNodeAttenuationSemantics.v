Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink GainNode Attenuation Semantics *)
(** Web Audio API 1 §4: output amplitude scaling non-negativity *)

Definition apply_gain (input_amp gain_factor : Z) : Z :=
  (input_amp * gain_factor) / 100.

Theorem gain_nonneg : forall i g,
  0 <= i ->
  0 <= g ->
  0 <= apply_gain i g.
Proof.
  intros i g Hi Hg.
  unfold apply_gain.
  apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia | lia].
Qed.
