Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebRTC DataChannel bufferedAmount Draining Semantics *)
(** WebRTC 1.0 §6.2: draining sent bytes monotonically decreases bufferedAmount *)

Definition drain_buffered_amount (current_buffered sent_bytes : Z) : Z :=
  Z.max 0 (current_buffered - sent_bytes).

Theorem drain_monotonically_decreases : forall b s,
  0 <= s ->
  0 <= b ->
  drain_buffered_amount b s <= b.
Proof.
  intros b s Hs Hb.
  unfold drain_buffered_amount.
  destruct (Z.max_spec 0 (b - s)) as [[H1 H2] | [H1 H2]]; rewrite H2; lia.
Qed.
