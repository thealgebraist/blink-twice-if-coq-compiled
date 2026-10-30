Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Streams BYOB Reader Buffer Transfer Clamping Semantics *)
(** Streams Standard §3.8: transferred bytes clamped to buffer capacity *)

Definition clamp_byob_read (requested_bytes buffer_capacity : Z) : Z :=
  Z.min (Z.max 0 requested_bytes) (Z.max 0 buffer_capacity).

Theorem byob_read_bounded : forall req cap,
  0 <= cap ->
  0 <= clamp_byob_read req cap <= cap.
Proof.
  intros req cap Hcap.
  unfold clamp_byob_read.
  assert (0 <= Z.max 0 cap) by lia.
  assert (Z.max 0 cap = cap) by lia.
  rewrite H0 in *.
  split.
  - apply Z.min_glb_iff. split; lia.
  - apply Z.le_min_r.
Qed.
