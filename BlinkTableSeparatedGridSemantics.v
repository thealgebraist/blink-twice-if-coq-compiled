(* ========================================================================= *)
(*               BlinkTableSeparatedGridSemantics.v                          *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Separated Borders Table Grid Geometry  *)
(* per W3C CSS 2.1 §17.6.1 (border-spacing & cell positioning).              *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition table_2x2_col_x (col_idx : nat) (w0 w1 sh : Z) : Z :=
  match col_idx with
  | 0%nat => sh
  | _ => sh + w0 + sh
  end.

Definition table_2x2_row_y (row_idx : nat) (h0 h1 sv : Z) : Z :=
  match row_idx with
  | 0%nat => sv
  | _ => sv + h0 + sv
  end.

Definition table_2x2_total_width (w0 w1 sh : Z) : Z :=
  sh + w0 + sh + w1 + sh.

Definition table_2x2_total_height (h0 h1 sv : Z) : Z :=
  sv + h0 + sv + h1 + sv.

Theorem table_2x2_columns_separated : forall w0 w1 sh,
  sh >= 0 ->
  table_2x2_col_x 0 w0 w1 sh + w0 <= table_2x2_col_x 1 w0 w1 sh.
Proof.
  intros w0 w1 sh Hsh.
  unfold table_2x2_col_x.
  lia.
Qed.

Theorem table_2x2_rows_separated : forall h0 h1 sv,
  sv >= 0 ->
  table_2x2_row_y 0 h0 h1 sv + h0 <= table_2x2_row_y 1 h0 h1 sv.
Proof.
  intros h0 h1 sv Hsv.
  unfold table_2x2_row_y.
  lia.
Qed.

Theorem table_2x2_width_decomposition : forall w0 w1 sh,
  table_2x2_total_width w0 w1 sh = w0 + w1 + 3 * sh.
Proof.
  intros.
  unfold table_2x2_total_width.
  ring.
Qed.

Theorem table_2x2_height_decomposition : forall h0 h1 sv,
  table_2x2_total_height h0 h1 sv = h0 + h1 + 3 * sv.
Proof.
  intros.
  unfold table_2x2_total_height.
  ring.
Qed.

Theorem table_2x2_contained_in_total_bounds : forall w0 w1 h0 h1 sh sv,
  w0 >= 0 -> w1 >= 0 -> h0 >= 0 -> h1 >= 0 ->
  sh >= 0 -> sv >= 0 ->
  0 <= table_2x2_col_x 0 w0 w1 sh /\
  table_2x2_col_x 1 w0 w1 sh + w1 <= table_2x2_total_width w0 w1 sh /\
  0 <= table_2x2_row_y 0 h0 h1 sv /\
  table_2x2_row_y 1 h0 h1 sv + h1 <= table_2x2_total_height h0 h1 sv.
Proof.
  intros w0 w1 h0 h1 sh sv Hw0 Hw1 Hh0 Hh1 Hsh Hsv.
  unfold table_2x2_col_x, table_2x2_row_y, table_2x2_total_width, table_2x2_total_height.
  repeat split; lia.
Qed.

