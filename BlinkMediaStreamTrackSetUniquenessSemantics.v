Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink MediaStream Track ID Distinctness Semantics *)
(** Media Capture and Streams §4.2: track collection distinct identity *)

Definition track_id_distinct (id1 id2 : Z) : bool :=
  negb (id1 =? id2).

Theorem track_uniqueness_sound : forall id1 id2,
  track_id_distinct id1 id2 = true <-> id1 <> id2.
Proof.
  intros id1 id2.
  unfold track_id_distinct.
  destruct (id1 =? id2) eqn:Heq.
  - apply Z.eqb_eq in Heq. split; [discriminate | intros H; exfalso; apply H; exact Heq].
  - apply Z.eqb_neq in Heq. split; [intros _; exact Heq | reflexivity].
Qed.
