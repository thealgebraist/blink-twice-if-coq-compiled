From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Blink Paint Properties Cumulative Paint Offset Propagation *)
Record PaintOffset := {
  po_x : Z;
  po_y : Z
}.

Definition propagate_paint_offset (parent child : PaintOffset) : PaintOffset :=
  {| po_x := po_x parent + po_x child;
     po_y := po_y parent + po_y child |}.

Definition zero_paint_offset : PaintOffset :=
  {| po_x := 0; po_y := 0 |}.

Theorem paint_offset_identity_left : forall p,
  propagate_paint_offset zero_paint_offset p = p.
Proof.
  intros [x y].
  unfold propagate_paint_offset, zero_paint_offset; cbn.
  f_equal; lia.
Qed.

Theorem paint_offset_identity_right : forall p,
  propagate_paint_offset p zero_paint_offset = p.
Proof.
  intros [x y].
  unfold propagate_paint_offset, zero_paint_offset; cbn.
  f_equal; lia.
Qed.

Theorem paint_offset_comm : forall p1 p2,
  propagate_paint_offset p1 p2 = propagate_paint_offset p2 p1.
Proof.
  intros [x1 y1] [x2 y2].
  unfold propagate_paint_offset; cbn.
  f_equal; lia.
Qed.
