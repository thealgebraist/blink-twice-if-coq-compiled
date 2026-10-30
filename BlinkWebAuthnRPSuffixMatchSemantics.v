Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebAuthn Relying Party ID Domain Match Semantics *)
(** WebAuthn Level 3 §5.1.3: RP ID matches origin domain suffix *)

Definition rp_id_matches (rp_len origin_len : Z) (is_suffix : bool) : bool :=
  is_suffix && (rp_len <=? origin_len).

Theorem rp_id_match_sound : forall r o s,
  rp_id_matches r o s = true ->
  r <= o /\ s = true.
Proof.
  intros r o s H.
  unfold rp_id_matches in H.
  apply andb_prop in H.
  destruct H as [Hs Hle].
  apply Z.leb_le in Hle.
  split; assumption.
Qed.
