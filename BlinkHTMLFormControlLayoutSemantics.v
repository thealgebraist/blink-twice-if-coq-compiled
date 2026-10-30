(* ========================================================================= *)
(*               BlinkHTMLFormControlLayoutSemantics.v                       *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink HTML Form Controls Layout (input,      *)
(* button) per HTML Living Standard §4.10 & CSS Form Controls 1.             *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition input_default_size : Z := 20.

Definition input_intrinsic_inline_size
  (char_w : Z) (size_attr : Z) (pad_inline : Z) (border_inline : Z) : Z :=
  let eff_size := Z.max 1 size_attr in
  eff_size * Z.max 0 char_w + Z.max 0 pad_inline + Z.max 0 border_inline.

Definition button_intrinsic_block_size
  (font_line_h : Z) (pad_block : Z) (border_block : Z) : Z :=
  Z.max 0 font_line_h + Z.max 0 pad_block + Z.max 0 border_block.

Theorem input_intrinsic_size_nonneg : forall cw s p b,
  input_intrinsic_inline_size cw s p b >= 0.
Proof.
  intros. unfold input_intrinsic_inline_size.
  pose proof (Z.le_max_l 1 s).
  pose proof (Z.le_max_l 0 cw).
  pose proof (Z.le_max_l 0 p).
  pose proof (Z.le_max_l 0 b).
  nia.
Qed.

Theorem button_intrinsic_size_nonneg : forall fh p b,
  button_intrinsic_block_size fh p b >= 0.
Proof.
  intros. unfold button_intrinsic_block_size.
  pose proof (Z.le_max_l 0 fh).
  pose proof (Z.le_max_l 0 p).
  pose proof (Z.le_max_l 0 b).
  lia.
Qed.

Theorem input_size_monotonic_in_attr : forall cw s1 s2 p b,
  1 <= s1 ->
  s1 <= s2 ->
  cw >= 0 ->
  input_intrinsic_inline_size cw s1 p b <= input_intrinsic_inline_size cw s2 p b.
Proof.
  intros cw s1 s2 p b Hs1 Hle Hcw.
  unfold input_intrinsic_inline_size.
  assert (Z.max 1 s1 = s1) by (apply Z.max_r; lia).
  assert (Z.max 1 s2 = s2) by (apply Z.max_r; lia).
  rewrite H, H0.
  assert (Z.max 0 cw = cw) by (apply Z.max_r; lia).
  rewrite H1.
  assert (s1 * cw <= s2 * cw) by nia.
  lia.
Qed.
