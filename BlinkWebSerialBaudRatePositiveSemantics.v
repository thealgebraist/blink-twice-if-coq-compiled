Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Web Serial Baud Rate Positive Semantics *)
(** Web Serial API §3.2 SerialOptions.baudRate validation *)

Definition is_valid_baud_rate (baud : Z) : bool :=
  (0 <? baud) && (baud <=? 4000000).

Theorem baud_rate_sound : forall baud,
  is_valid_baud_rate baud = true ->
  0 < baud <= 4000000.
Proof.
  intros baud H.
  unfold is_valid_baud_rate in H.
  apply andb_prop in H.
  destruct H as [Hgt Hle].
  apply Z.ltb_lt in Hgt.
  apply Z.leb_le in Hle.
  split; assumption.
Qed.
