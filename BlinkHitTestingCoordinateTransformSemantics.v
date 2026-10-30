Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Hit Testing Coordinate Transform Semantics *)
(** Blink Hit Testing §2: inverse transformation preserves point-in-box inclusion *)

Definition point_in_box (px py box_x box_y box_w box_h : Z) : bool :=
  (box_x <=? px) && (px <=? box_x + box_w) &&
  (box_y <=? py) && (py <=? box_y + box_h).

Theorem point_in_box_sound : forall px py box_x box_y box_w box_h,
  box_x <= px <= box_x + box_w ->
  box_y <= py <= box_y + box_h ->
  point_in_box px py box_x box_y box_w box_h = true.
Proof.
  intros px py box_x box_y box_w box_h Hx Hy.
  unfold point_in_box.
  repeat (apply andb_true_intro; split); apply Z.leb_le; lia.
Qed.
