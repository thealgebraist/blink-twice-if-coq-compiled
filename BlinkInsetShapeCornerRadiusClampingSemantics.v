Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Inset Shape Corner Radius Clamping Semantics *)
(** CSS Shapes 1 §3.1: inset() round corner radius scaling *)

Definition is_corner_radius_valid (r1 r2 width : Z) : bool :=
  (0 <=? r1) && (0 <=? r2) && (r1 + r2 <=? width).

Theorem corner_radius_sound : forall r1 r2 w,
  is_corner_radius_valid r1 r2 w = true ->
  0 <= r1 /\ 0 <= r2 /\ r1 + r2 <= w.
Proof.
  intros r1 r2 w H.
  unfold is_corner_radius_valid in H.
  apply andb_prop in H.
  destruct H as [H1 Hw].
  apply andb_prop in H1.
  destruct H1 as [Hr1 Hr2].
  apply Z.leb_le in Hr1.
  apply Z.leb_le in Hr2.
  apply Z.leb_le in Hw.
  repeat split; assumption.
Qed.
