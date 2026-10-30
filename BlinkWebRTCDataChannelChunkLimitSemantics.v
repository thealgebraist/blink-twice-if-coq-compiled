Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC DataChannel Message Chunk Limit Semantics *)
(** RFC 8831 §6.6: packet chunk size bounded by 65536 bytes *)

Definition MAX_DATA_CHANNEL_CHUNK : Z := 65536.

Definition clamp_chunk_size (requested_bytes : Z) : Z :=
  Z.min (Z.max 0 requested_bytes) MAX_DATA_CHANNEL_CHUNK.

Theorem chunk_size_bounded_by_max : forall r,
  0 <= clamp_chunk_size r <= MAX_DATA_CHANNEL_CHUNK.
Proof.
  intros r.
  unfold clamp_chunk_size, MAX_DATA_CHANNEL_CHUNK.
  split.
  - apply Z.min_glb_iff. split; [apply Z.le_max_l | lia].
  - apply Z.le_min_r.
Qed.
