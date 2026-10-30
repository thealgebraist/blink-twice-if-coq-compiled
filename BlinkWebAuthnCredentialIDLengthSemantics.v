Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebAuthn Credential ID Length Bounds Semantics *)
(** WebAuthn Level 3 §5.1.3: credential ID length in [1, 1023] bytes *)

Definition is_valid_credential_id_length (len : Z) : bool :=
  (0 <? len) && (len <=? 1023).

Theorem cred_id_length_sound : forall l,
  is_valid_credential_id_length l = true <-> (0 < l /\ l <= 1023).
Proof.
  intros l.
  unfold is_valid_credential_id_length.
  rewrite andb_true_iff, Z.ltb_lt, Z.leb_le.
  tauto.
Qed.
