Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto PBKDF2 Iterations Semantics *)
(** Web Cryptography API §30.2: iterations must be positive integer >= 1 *)

Definition is_valid_iterations (iter : Z) : bool :=
  1 <=? iter.

Theorem iterations_sound : forall iter,
  is_valid_iterations iter = true <-> 1 <= iter.
Proof.
  intros iter.
  unfold is_valid_iterations.
  apply Z.leb_le.
Qed.
