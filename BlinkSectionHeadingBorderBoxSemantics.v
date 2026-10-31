(* BlinkSectionHeadingBorderBoxSemantics.v *)
(* Formal semantics of Blink Section Heading border-bottom placement *)
(* Modeled after Chromium third_party/blink/renderer/core/layout/ng/ng_block_layout_algorithm.cc *)

Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record BlinkHeadingBox := mkHeadingBox {
  hb_top_y : Z;
  hb_font_size : Z;
  hb_line_height : Z;
  hb_padding_bottom : Z;
  hb_border_bottom_width : Z
}.

Definition compute_heading_border_y (h : BlinkHeadingBox) : Z :=
  hb_top_y h + hb_line_height h + hb_padding_bottom h.

Definition compute_heading_text_baseline (h : BlinkHeadingBox) : Z :=
  hb_top_y h + hb_font_size h - 1.

Theorem border_strictly_below_text_baseline :
  forall (h : BlinkHeadingBox),
    0 <= hb_padding_bottom h ->
    hb_font_size h <= hb_line_height h ->
    compute_heading_text_baseline h < compute_heading_border_y h.
Proof.
  intros h Hpad Hfit.
  unfold compute_heading_text_baseline, compute_heading_border_y.
  lia.
Qed.

(* Exact Page 2 Section 1.2 Heading parameters:
   Top = 269, Font size = 16, Line height = 16, Padding bottom = 3, Border = 1
   Text baseline = 269 + 16 - 1 = 284
   Border Y = 269 + 16 + 3 = 288 *)
Definition p2_section_1_2_heading : BlinkHeadingBox := mkHeadingBox 269 16 16 3 1.

Theorem p2_section_1_2_heading_exact :
  compute_heading_text_baseline p2_section_1_2_heading = 284 /\
  compute_heading_border_y p2_section_1_2_heading = 288.
Proof.
  unfold compute_heading_text_baseline, compute_heading_border_y, p2_section_1_2_heading.
  split; reflexivity.
Qed.
