(* ========================================================================= *)
(*               BlinkHTMLUASheetSemantics.v                                 *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Default User Agent Stylesheet          *)
(* per HTML Living Standard §15 (Body, Headers, Table, TR, TD, TH).         *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Inductive HTMLTag :=
  | TagBody
  | TagH1
  | TagH2
  | TagH3
  | TagH4
  | TagH5
  | TagH6
  | TagTable
  | TagTR
  | TagTD
  | TagTH
  | TagP.

Definition DISPLAY_BLOCK : Z := 1.
Definition DISPLAY_TABLE : Z := 2.
Definition DISPLAY_TABLE_ROW : Z := 3.
Definition DISPLAY_TABLE_CELL : Z := 4.
Definition DISPLAY_INLINE : Z := 5.

Record UAStyle := mkUAStyle {
  ua_display : Z;
  ua_font_size : Z;
  ua_font_weight_bold : bool;
  ua_margin_top : Z;
  ua_margin_bottom : Z;
  ua_margin_inline : Z;
  ua_padding : Z;
  ua_border_spacing : Z;
  ua_text_align_center : bool
}.

Definition get_ua_style (tag : HTMLTag) : UAStyle :=
  match tag with
  | TagBody =>
      {| ua_display := DISPLAY_BLOCK;
         ua_font_size := 16;
         ua_font_weight_bold := false;
         ua_margin_top := 8;
         ua_margin_bottom := 8;
         ua_margin_inline := 8;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagH1 =>
      {| ua_display := DISPLAY_BLOCK;
         ua_font_size := 32;
         ua_font_weight_bold := true;
         ua_margin_top := 21;
         ua_margin_bottom := 21;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagH2 =>
      {| ua_display := DISPLAY_BLOCK;
         ua_font_size := 24;
         ua_font_weight_bold := true;
         ua_margin_top := 20;
         ua_margin_bottom := 20;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagH3 =>
      {| ua_display := DISPLAY_BLOCK;
         ua_font_size := 19;
         ua_font_weight_bold := true;
         ua_margin_top := 19;
         ua_margin_bottom := 19;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagH4 =>
      {| ua_display := DISPLAY_BLOCK;
         ua_font_size := 16;
         ua_font_weight_bold := true;
         ua_margin_top := 21;
         ua_margin_bottom := 21;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagH5 =>
      {| ua_display := DISPLAY_BLOCK;
         ua_font_size := 13;
         ua_font_weight_bold := true;
         ua_margin_top := 22;
         ua_margin_bottom := 22;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagH6 =>
      {| ua_display := DISPLAY_BLOCK;
         ua_font_size := 11;
         ua_font_weight_bold := true;
         ua_margin_top := 25;
         ua_margin_bottom := 25;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagTable =>
      {| ua_display := DISPLAY_TABLE;
         ua_font_size := 16;
         ua_font_weight_bold := false;
         ua_margin_top := 0;
         ua_margin_bottom := 0;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 2;
         ua_text_align_center := false |}
  | TagTR =>
      {| ua_display := DISPLAY_TABLE_ROW;
         ua_font_size := 16;
         ua_font_weight_bold := false;
         ua_margin_top := 0;
         ua_margin_bottom := 0;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagTD =>
      {| ua_display := DISPLAY_TABLE_CELL;
         ua_font_size := 16;
         ua_font_weight_bold := false;
         ua_margin_top := 0;
         ua_margin_bottom := 0;
         ua_margin_inline := 0;
         ua_padding := 1;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  | TagTH =>
      {| ua_display := DISPLAY_TABLE_CELL;
         ua_font_size := 16;
         ua_font_weight_bold := true;
         ua_margin_top := 0;
         ua_margin_bottom := 0;
         ua_margin_inline := 0;
         ua_padding := 1;
         ua_border_spacing := 0;
         ua_text_align_center := true |}
  | TagP =>
      {| ua_display := DISPLAY_BLOCK;
         ua_font_size := 16;
         ua_font_weight_bold := false;
         ua_margin_top := 16;
         ua_margin_bottom := 16;
         ua_margin_inline := 0;
         ua_padding := 0;
         ua_border_spacing := 0;
         ua_text_align_center := false |}
  end.

Theorem ua_metrics_nonneg : forall tag,
  let s := get_ua_style tag in
  ua_font_size s > 0 /\
  ua_margin_top s >= 0 /\
  ua_margin_bottom s >= 0 /\
  ua_margin_inline s >= 0 /\
  ua_padding s >= 0 /\
  ua_border_spacing s >= 0.
Proof.
  intros tag.
  destruct tag; cbn; repeat split; lia.
Qed.

Theorem th_has_bold_and_centered :
  let s := get_ua_style TagTH in
  ua_font_weight_bold s = true /\ ua_text_align_center s = true.
Proof.
  cbn. split; reflexivity.
Qed.

Theorem table_has_table_display_and_spacing :
  let s := get_ua_style TagTable in
  ua_display s = DISPLAY_TABLE /\ ua_border_spacing s = 2.
Proof.
  cbn. split; reflexivity.
Qed.

Theorem h1_font_size_gt_h2 :
  ua_font_size (get_ua_style TagH1) > ua_font_size (get_ua_style TagH2).
Proof.
  cbn. lia.
Qed.

Theorem h2_font_size_gt_body :
  ua_font_size (get_ua_style TagH2) > ua_font_size (get_ua_style TagBody).
Proof.
  cbn. lia.
Qed.

