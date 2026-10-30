Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink PasswordCredential Non-Empty Fields Semantics *)
(** Credential Management Level 1 §5.1: non-empty username and password *)

Definition is_valid_password_credential (username_len password_len : Z) : bool :=
  (0 <? username_len) && (0 <? password_len).

Theorem password_cred_sound : forall u p,
  is_valid_password_credential u p = true <-> (0 < u /\ 0 < p).
Proof.
  intros u p.
  unfold is_valid_password_credential.
  rewrite andb_true_iff, Z.ltb_lt, Z.ltb_lt.
  tauto.
Qed.
