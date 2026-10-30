Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink BiquadFilter Cutoff Frequency Clamping Semantics *)
(** Web Audio API 1 §4: cutoff frequency clamped within [0, Nyquist] *)

Definition clamp_cutoff_frequency (freq nyquist : Z) : Z :=
  Z.max 0 (Z.min nyquist freq).

Theorem cutoff_bounded : forall f ny,
  0 <= ny ->
  0 <= clamp_cutoff_frequency f ny <= ny.
Proof.
  intros f ny Hny.
  unfold clamp_cutoff_frequency; lia.
Qed.
