Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Phone Number E.164 Normalization Semantics *)
(** ITU-T E.164 phone number international format *)

Definition is_valid_e164 (has_leading_plus : bool) (digit_count : Z) : bool :=
  has_leading_plus && (1 <=? digit_count) && (digit_count <=? 15).

Theorem e164_soundness : forall plus count,
  is_valid_e164 plus count = true ->
  plus = true /\ 1 <= count <= 15.
Proof.
  intros plus count H.
  unfold is_valid_e164 in H.
  apply andb_prop in H.
  destruct H as [H1 Hle].
  apply andb_prop in H1.
  destruct H1 as [Hplus Hge].
  apply Z.leb_le in Hge.
  apply Z.leb_le in Hle.
  split; [exact Hplus | split; assumption].
Qed.
