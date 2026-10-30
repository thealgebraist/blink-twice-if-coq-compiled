Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAuthn Extension Outputs Idempotence Semantics *)
(** WebAuthn Level 3 §9: extension outputs evaluation determinism *)

Definition eval_extension (input : Z) : Z :=
  input.

Theorem extension_eval_idempotent : forall i,
  eval_extension (eval_extension i) = eval_extension i.
Proof.
  intros i.
  reflexivity.
Qed.
