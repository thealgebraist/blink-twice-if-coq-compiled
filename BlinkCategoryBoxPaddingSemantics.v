(* BlinkCategoryBoxPaddingSemantics.v *)
(* Formal semantics of Blink Block Layout padding and border-box inner baseline computation *)
(* Modeled after Chromium third_party/blink/renderer/core/layout/ng/ng_block_layout_algorithm.cc *)

Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record BlinkBlockBox := mkBlockBox {
  bb_left : Z;
  bb_top : Z;
  bb_border_left : Z;
  bb_border_top : Z;
  bb_padding_left : Z;
  bb_padding_top : Z;
  bb_font_ascent : Z
}.

Definition compute_inner_content_x (b : BlinkBlockBox) : Z :=
  bb_left b + bb_border_left b + bb_padding_left b.

Definition compute_inner_baseline_y (b : BlinkBlockBox) : Z :=
  bb_top b + bb_border_top b + bb_padding_top b + bb_font_ascent b.

Theorem inner_content_strictly_contained :
  forall (b : BlinkBlockBox),
    0 <= bb_border_left b ->
    0 <= bb_padding_left b ->
    bb_left b <= compute_inner_content_x b.
Proof.
  intros b Hb Hp.
  unfold compute_inner_content_x.
  lia.
Qed.

Theorem inner_baseline_monotonic :
  forall (b : BlinkBlockBox),
    0 <= bb_border_top b ->
    0 <= bb_padding_top b ->
    0 <= bb_font_ascent b ->
    bb_top b <= compute_inner_baseline_y b.
Proof.
  intros b Hb Hp Ha.
  unfold compute_inner_baseline_y.
  lia.
Qed.

(* Exact Page 3 Category Box parameters:
   Left = 25, Top = 446, Border = 1, Padding left = 12, Padding top = 6, Ascent = 8
   Inner X = 25 + 1 + 12 = 38
   Inner Y = 446 + 1 + 6 + 8 = 461 *)
Definition p3_category_box : BlinkBlockBox := mkBlockBox 25 446 1 1 12 6 8.

Theorem p3_category_box_coordinates_exact :
  compute_inner_content_x p3_category_box = 38 /\
  compute_inner_baseline_y p3_category_box = 461.
Proof.
  unfold compute_inner_content_x, compute_inner_baseline_y, p3_category_box.
  split; reflexivity.
Qed.
