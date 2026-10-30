Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC Jitter Buffer Delay Clamping Semantics *)
(** RFC 3550 §6.4.1: delay clamped within [min_delay, max_delay] *)

Definition clamp_jitter_delay (target min_delay max_delay : Z) : Z :=
  Z.min max_delay (Z.max min_delay target).

Theorem jitter_delay_clamped_in_bounds : forall tgt min_d max_d,
  min_d <= max_d ->
  min_d <= clamp_jitter_delay tgt min_d max_d <= max_d.
Proof.
  intros tgt min_d max_d Hle.
  unfold clamp_jitter_delay.
  split.
  - apply Z.min_glb_iff. split; [lia | apply Z.le_max_l].
  - apply Z.le_min_l.
Qed.
