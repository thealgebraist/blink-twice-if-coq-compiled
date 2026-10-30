Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Ruby Base and Text Alignment Semantics *)
(** CSS Ruby Layout 1 §3: ruby column width and centering *)

Definition ruby_column_width (base_w text_w : Z) : Z :=
  Z.max base_w text_w.

Definition ruby_centering_offset (col_w item_w : Z) : Z :=
  (col_w - item_w) / 2.

Theorem centering_offset_nonneg : forall col_w item_w,
  item_w <= col_w ->
  ruby_centering_offset col_w item_w >= 0.
Proof.
  intros col_w item_w Hle.
  unfold ruby_centering_offset.
  assert (col_w - item_w >= 0) by lia.
  assert (Hpos : 0 < 2) by lia.
  assert (0 <= (col_w - item_w) / 2).
  { apply Z.div_pos; lia. }
  lia.
Qed.
