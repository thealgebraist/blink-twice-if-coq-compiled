(* ========================================================================= *)
(*               BlinkTableCellNonOverlapSemantics.v                         *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Table Cell Non-Overlap & Disjointness  *)
(* per W3C CSS 2.1 §17.5.                                                   *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Require Import BlinkTableSeparatedGridSemantics.
Open Scope Z_scope.

Definition rect_disjoint_2d (x1 y1 w1 h1 x2 y2 w2 h2 : Z) : Prop :=
  (x1 + w1 <= x2 \/ x2 + w2 <= x1) \/
  (y1 + h1 <= y2 \/ y2 + h2 <= y1).

Theorem cell_00_and_01_disjoint : forall w0 w1 h0 h1 sh sv,
  sh >= 0 ->
  rect_disjoint_2d
    (table_2x2_col_x 0 w0 w1 sh) (table_2x2_row_y 0 h0 h1 sv) w0 h0
    (table_2x2_col_x 1 w0 w1 sh) (table_2x2_row_y 0 h0 h1 sv) w1 h0.
Proof.
  intros w0 w1 h0 h1 sh sv Hsh.
  unfold rect_disjoint_2d, table_2x2_col_x.
  left. left. lia.
Qed.

Theorem cell_10_and_11_disjoint : forall w0 w1 h0 h1 sh sv,
  sh >= 0 ->
  rect_disjoint_2d
    (table_2x2_col_x 0 w0 w1 sh) (table_2x2_row_y 1 h0 h1 sv) w0 h1
    (table_2x2_col_x 1 w0 w1 sh) (table_2x2_row_y 1 h0 h1 sv) w1 h1.
Proof.
  intros w0 w1 h0 h1 sh sv Hsh.
  unfold rect_disjoint_2d, table_2x2_col_x.
  left. left. lia.
Qed.

Theorem cell_00_and_10_disjoint : forall w0 w1 h0 h1 sh sv,
  sv >= 0 ->
  rect_disjoint_2d
    (table_2x2_col_x 0 w0 w1 sh) (table_2x2_row_y 0 h0 h1 sv) w0 h0
    (table_2x2_col_x 0 w0 w1 sh) (table_2x2_row_y 1 h0 h1 sv) w0 h1.
Proof.
  intros w0 w1 h0 h1 sh sv Hsv.
  unfold rect_disjoint_2d, table_2x2_row_y.
  right. left. lia.
Qed.

Theorem cell_01_and_11_disjoint : forall w0 w1 h0 h1 sh sv,
  sv >= 0 ->
  rect_disjoint_2d
    (table_2x2_col_x 1 w0 w1 sh) (table_2x2_row_y 0 h0 h1 sv) w1 h0
    (table_2x2_col_x 1 w0 w1 sh) (table_2x2_row_y 1 h0 h1 sv) w1 h1.
Proof.
  intros w0 w1 h0 h1 sh sv Hsv.
  unfold rect_disjoint_2d, table_2x2_row_y.
  right. left. lia.
Qed.

Theorem cell_00_and_11_disjoint : forall w0 w1 h0 h1 sh sv,
  sh >= 0 -> sv >= 0 ->
  rect_disjoint_2d
    (table_2x2_col_x 0 w0 w1 sh) (table_2x2_row_y 0 h0 h1 sv) w0 h0
    (table_2x2_col_x 1 w0 w1 sh) (table_2x2_row_y 1 h0 h1 sv) w1 h1.
Proof.
  intros w0 w1 h0 h1 sh sv Hsh Hsv.
  unfold rect_disjoint_2d, table_2x2_col_x, table_2x2_row_y.
  left. left. lia.
Qed.

Theorem cell_01_and_10_disjoint : forall w0 w1 h0 h1 sh sv,
  sh >= 0 -> sv >= 0 ->
  rect_disjoint_2d
    (table_2x2_col_x 1 w0 w1 sh) (table_2x2_row_y 0 h0 h1 sv) w1 h0
    (table_2x2_col_x 0 w0 w1 sh) (table_2x2_row_y 1 h0 h1 sv) w0 h1.
Proof.
  intros w0 w1 h0 h1 sh sv Hsh Hsv.
  unfold rect_disjoint_2d, table_2x2_col_x, table_2x2_row_y.
  right. left. lia.
Qed.

