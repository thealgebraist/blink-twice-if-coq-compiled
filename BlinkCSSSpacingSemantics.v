(* ========================================================================= *)
(*               BlinkCSSSpacingSemantics.v                                  *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Letter Spacing & Word Spacing          *)
(* per W3C CSS Text Module Level 3 §8.                                       *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition compute_spaced_run_width
  (char_count : Z) (glyph_w : Z)
  (letter_spacing : Z) (word_count : Z) (word_spacing : Z) : Z :=
  if char_count <=? 0 then 0
  else char_count * glyph_w + (char_count - 1) * letter_spacing + word_count * word_spacing.

Theorem spaced_run_width_zero_chars : forall glyph_w ls wc ws,
  compute_spaced_run_width 0 glyph_w ls wc ws = 0.
Proof.
  intros. unfold compute_spaced_run_width. simpl. reflexivity.
Qed.

Theorem spaced_run_width_nonneg : forall char_count glyph_w ls wc ws,
  char_count >= 1 ->
  glyph_w >= 0 ->
  ls >= 0 ->
  wc >= 0 ->
  ws >= 0 ->
  compute_spaced_run_width char_count glyph_w ls wc ws >= 0.
Proof.
  intros char_count glyph_w ls wc ws Hc Hg Hls Hwc Hws.
  unfold compute_spaced_run_width.
  destruct (char_count <=? 0) eqn:E; [lia |].
  assert (char_count * glyph_w >= 0) by nia.
  assert ((char_count - 1) * ls >= 0) by nia.
  assert (wc * ws >= 0) by nia.
  lia.
Qed.

Theorem spaced_run_width_monotonic_ls : forall char_count glyph_w ls1 ls2 wc ws,
  char_count >= 1 ->
  ls1 <= ls2 ->
  compute_spaced_run_width char_count glyph_w ls1 wc ws <=
  compute_spaced_run_width char_count glyph_w ls2 wc ws.
Proof.
  intros char_count glyph_w ls1 ls2 wc ws Hc Hle.
  unfold compute_spaced_run_width.
  destruct (char_count <=? 0) eqn:E; [lia |].
  assert ((char_count - 1) * ls1 <= (char_count - 1) * ls2) by nia.
  lia.
Qed.

Theorem spaced_run_width_monotonic_ws : forall char_count glyph_w ls wc1 wc2 ws,
  char_count >= 1 ->
  wc1 <= wc2 ->
  ws >= 0 ->
  compute_spaced_run_width char_count glyph_w ls wc1 ws <=
  compute_spaced_run_width char_count glyph_w ls wc2 ws.
Proof.
  intros char_count glyph_w ls wc1 wc2 ws Hc Hle Hws.
  unfold compute_spaced_run_width.
  destruct (char_count <=? 0) eqn:E; [lia |].
  assert (wc1 * ws <= wc2 * ws) by nia.
  lia.
Qed.
