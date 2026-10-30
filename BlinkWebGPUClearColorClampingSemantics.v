Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebGPU Clear Color Channel Clamping Semantics *)
(** WebGPU §10.1: channel intensity clamped to [0, 255] *)

Definition clamp_clear_channel (c : Z) : Z :=
  Z.min 255 (Z.max 0 c).

Theorem clear_channel_bounded : forall c,
  0 <= clamp_clear_channel c <= 255.
Proof.
  intros c.
  unfold clamp_clear_channel.
  split.
  - apply Z.min_glb_iff. split; [lia | apply Z.le_max_l].
  - apply Z.le_min_l.
Qed.
