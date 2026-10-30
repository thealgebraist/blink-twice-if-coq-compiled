Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Shape Detection Bounding Box Semantics *)
(** Shape Detection API §3: detected bounding box dimensions non-negative *)

Record detected_box : Type := mk_detected_box {
  box_w : Z;
  box_h : Z
}.

Definition is_valid_detected_box (b : detected_box) : bool :=
  (0 <=? box_w b) && (0 <=? box_h b).

Theorem detected_box_sound : forall b,
  is_valid_detected_box b = true ->
  box_w b >= 0 /\ box_h b >= 0.
Proof.
  intros [w h] H.
  unfold is_valid_detected_box in H; simpl in H.
  apply andb_prop in H.
  destruct H as [Hw Hh].
  apply Z.leb_le in Hw.
  apply Z.leb_le in Hh.
  simpl.
  lia.
Qed.
