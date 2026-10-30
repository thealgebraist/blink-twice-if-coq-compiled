Require Import Bool.

(** * Blink WebAuthn Resident Key Flag Consistency Semantics *)
(** WebAuthn Level 3 §5.1.2: discoverable credential eligibility *)

Definition is_resident_key_eligible (rk_supported client_requested : bool) : bool :=
  rk_supported && client_requested.

Theorem rk_requires_both : forall s r,
  is_resident_key_eligible s r = true ->
  s = true /\ r = true.
Proof.
  intros s r H.
  unfold is_resident_key_eligible in H.
  apply andb_prop in H.
  exact H.
Qed.
