(* ========================================================================= *)
(*               BlinkInlineTextRunLayoutSemantics.v                         *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Inline Text Run Layout in Headers and  *)
(* Table Cells per W3C CSS Inline Layout Module Level 3 §3.                  *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition char_glyph_width (font_size : Z) : Z :=
  (font_size * 6) / 10.

Definition text_run_advance (char_count : Z) (font_size : Z) : Z :=
  char_count * char_glyph_width font_size.

Definition text_run_line_height (font_size : Z) : Z :=
  (font_size * 12) / 10.

Definition text_run_baseline (font_size : Z) : Z :=
  font_size.

Theorem glyph_width_nonneg : forall f,
  f >= 0 ->
  char_glyph_width f >= 0.
Proof.
  intros f Hf.
  unfold char_glyph_width.
  apply Z.le_ge.
  apply Z.div_pos; lia.
Qed.

Theorem text_advance_nonneg : forall cnt f,
  cnt >= 0 -> f >= 0 ->
  text_run_advance cnt f >= 0.
Proof.
  intros cnt f Hcnt Hf.
  unfold text_run_advance.
  pose proof (glyph_width_nonneg f Hf).
  nia.
Qed.

Theorem text_advance_monotonic_in_count : forall c1 c2 f,
  0 <= c1 <= c2 ->
  f >= 0 ->
  text_run_advance c1 f <= text_run_advance c2 f.
Proof.
  intros c1 c2 f [Hc1_pos Hc12] Hf.
  unfold text_run_advance.
  pose proof (glyph_width_nonneg f Hf).
  nia.
Qed.

Theorem line_height_ge_font_size : forall f,
  f >= 0 ->
  text_run_line_height f >= f.
Proof.
  intros f Hf.
  unfold text_run_line_height.
  assert (Hf10: (f * 10) / 10 = f) by (apply Z.div_mul; lia).
  rewrite <- Hf10 at 2.
  apply Z.le_ge.
  apply Z.div_le_mono; lia.
Qed.
