Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC Audio Gain Clamping Semantics *)
(** WebRTC 1.0 §5.2: audio gain basis points clamped within [0, 1000] *)

Definition clamp_audio_gain (gain : Z) : Z :=
  Z.min 1000 (Z.max 0 gain).

Theorem audio_gain_bounded : forall g,
  0 <= clamp_audio_gain g <= 1000.
Proof.
  intros g.
  unfold clamp_audio_gain.
  split.
  - apply Z.min_glb_iff. split; [lia | apply Z.le_max_l].
  - apply Z.le_min_l.
Qed.
