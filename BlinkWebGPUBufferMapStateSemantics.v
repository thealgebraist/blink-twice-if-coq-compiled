Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebGPU Buffer Map State Semantics *)
(** WebGPU §6.2.1: buffer mapping states; unmap resets to unmapped *)

Definition MAP_STATE_UNMAPPED : Z := 0.
Definition MAP_STATE_PENDING  : Z := 1.
Definition MAP_STATE_MAPPED   : Z := 2.

Definition unmap_buffer (st : Z) : Z :=
  MAP_STATE_UNMAPPED.

Theorem unmap_resets_state : forall st,
  unmap_buffer st = MAP_STATE_UNMAPPED.
Proof.
  intros st.
  reflexivity.
Qed.
