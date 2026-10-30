(* ========================================================================= *)
(*               BlinkHTMLParagraphLayoutSemantics.v                         *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink HTML Paragraph Layout and             *)
(* Inter-Paragraph Margin Collapsing per HTML Standard §4.4.1 & CSS 2.1 §9.4.1*)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Lia.
Require Import BlinkHeaderMarginCollapsingSemantics.
Open Scope Z_scope.

Definition p_ua_margin_top : Z := 16.
Definition p_ua_margin_bottom : Z := 16.

Definition inter_paragraph_spacing : Z :=
  collapse_margins p_ua_margin_bottom p_ua_margin_top.

Theorem default_inter_p_spacing_exact :
  inter_paragraph_spacing = 16.
Proof.
  unfold inter_paragraph_spacing, p_ua_margin_top, p_ua_margin_bottom.
  unfold collapse_margins.
  reflexivity.
Qed.

Record ParagraphBox := mkParagraphBox {
  pb_height : Z;
  pb_margin_top : Z;
  pb_margin_bottom : Z
}.

Definition advance_paragraph_cursor (y : Z) (p : ParagraphBox) (next_mt : Z) : Z :=
  let eff_h := Z.max 0 (pb_height p) in
  let collapsed := collapse_margins (pb_margin_bottom p) next_mt in
  y + eff_h + collapsed.

Theorem advance_p_cursor_monotonic : forall y p next_mt,
  pb_margin_bottom p >= 0 ->
  next_mt >= 0 ->
  y <= advance_paragraph_cursor y p next_mt.
Proof.
  intros y p next_mt Hmb Hmt.
  unfold advance_paragraph_cursor.
  pose proof (collapse_margins_nonneg_bounds (pb_margin_bottom p) next_mt Hmb Hmt) as [Hlow _].
  pose proof (Z.le_max_l 0 (pb_height p)).
  lia.
Qed.

Theorem advance_p_cursor_strictly_increasing : forall y p next_mt,
  pb_height p > 0 ->
  pb_margin_bottom p >= 0 ->
  next_mt >= 0 ->
  y < advance_paragraph_cursor y p next_mt.
Proof.
  intros y p next_mt Hh Hmb Hmt.
  unfold advance_paragraph_cursor.
  pose proof (collapse_margins_nonneg_bounds (pb_margin_bottom p) next_mt Hmb Hmt) as [Hlow _].
  assert (Z.max 0 (pb_height p) = pb_height p) by (apply Z.max_r; lia).
  lia.
Qed.

Fixpoint layout_paragraphs (y : Z) (ps : list ParagraphBox) : Z :=
  match ps with
  | nil => y
  | p :: rest =>
      let next_mt := match rest with
                     | nil => 0
                     | next_p :: _ => pb_margin_top next_p
                     end in
      layout_paragraphs (advance_paragraph_cursor y p next_mt) rest
  end.

Theorem layout_empty_paragraphs : forall y,
  layout_paragraphs y nil = y.
Proof.
  reflexivity.
Qed.
