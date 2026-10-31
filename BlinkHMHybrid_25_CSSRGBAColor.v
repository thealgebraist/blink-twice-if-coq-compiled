(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CSSRGBAColor := mkCSSRGBAColor {
  cssrgbacolor_r : Z;
  cssrgbacolor_g : Z;
  cssrgbacolor_b : Z;
  cssrgbacolor_a : Z
}.

Definition premultiply_channel (chan : Z) (alpha : Z) : Z :=
  (chan * alpha) / 255.

Theorem premultiply_channel_bounded :
  forall (chan alpha : Z), 0 <= chan <= 255 -> 0 <= alpha <= 255 -> 0 <= premultiply_channel chan alpha <= chan.
Proof.
  intros chan alpha Hc Ha.
  unfold premultiply_channel. split.
  - apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia | lia].
  - apply Z.div_le_upper_bound; [lia |].
    assert (Hmul : chan * alpha <= chan * 255) by (apply Z.mul_le_mono_nonneg_l; lia).
    lia.
Qed.
