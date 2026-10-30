Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Background Fetch Progress Monotonicity Semantics *)
(** Background Fetch API §4.1: downloaded progress monotonic non-decreasing *)

Definition advance_download (prev next total : Z) : bool :=
  (0 <=? prev) && (prev <=? next) && (next <=? total).

Theorem advance_download_sound : forall prev next total,
  advance_download prev next total = true ->
  0 <= prev /\ prev <= next /\ next <= total.
Proof.
  intros prev next total H.
  unfold advance_download in H.
  apply andb_prop in H.
  destruct H as [H1 Htot].
  apply andb_prop in H1.
  destruct H1 as [H0 Hpn].
  apply Z.leb_le in H0.
  apply Z.leb_le in Hpn.
  apply Z.leb_le in Htot.
  split; [exact H0 | split; assumption].
Qed.
