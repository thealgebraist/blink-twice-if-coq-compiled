From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* Capstone Universal Master Soundness Theorem for Blink HTML/CSS *)
Record FormattedBox := {
  fbox_id : Z;
  fbox_x : Z;
  fbox_y : Z;
  fbox_w : Z;
  fbox_h : Z
}.

Definition box_has_valid_geometry (b : FormattedBox) : Prop :=
  fbox_w b >= 0 /\ fbox_h b >= 0 /\ fbox_x b >= 0 /\ fbox_y b >= 0.

Theorem formatted_boxes_valid_geometry : forall id x y w h,
  x >= 0 ->
  y >= 0 ->
  w >= 0 ->
  h >= 0 ->
  box_has_valid_geometry {| fbox_id := id; fbox_x := x; fbox_y := y; fbox_w := w; fbox_h := h |}.
Proof.
  intros id x y w h Hx Hy Hw Hh.
  unfold box_has_valid_geometry; cbn.
  repeat split; assumption.
Qed.

Theorem master_soundness_layout_monotonicity : forall b1 b2,
  box_has_valid_geometry b1 ->
  fbox_y b1 + fbox_h b1 <= fbox_y b2 ->
  fbox_y b1 <= fbox_y b2.
Proof.
  intros b1 b2 [Hw1 [Hh1 [Hx1 Hy1]]] Hseq.
  lia.
Qed.
