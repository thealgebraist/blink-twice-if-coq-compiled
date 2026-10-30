Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Screen Wake Lock Sentinel Semantics *)
(** Screen Wake Lock API §4: release() sets released to true idempotently *)

Definition release_wake_lock (released : bool) : bool :=
  true.

Theorem wake_lock_release_idempotent : forall r,
  release_wake_lock (release_wake_lock r) = release_wake_lock r.
Proof.
  intros r.
  reflexivity.
Qed.
