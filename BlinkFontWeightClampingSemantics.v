From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Fonts 4 §5 Font-Weight Normalization & Clamping *)
Definition clamp_font_weight (w : Z) : Z :=
  Z.max 1 (Z.min 1000 w).

Theorem font_weight_bounded : forall w,
  1 <= clamp_font_weight w <= 1000.
Proof.
  intros w.
  unfold clamp_font_weight.
  assert (Z.max 1 (Z.min 1000 w) >= 1) by (apply Z.le_ge; apply Z.le_max_l).
  assert (Z.min 1000 w <= 1000) by (apply Z.le_min_l).
  destruct (Z.max_dec 1 (Z.min 1000 w)); lia.
Qed.

Theorem font_weight_idempotent_in_range : forall w,
  1 <= w <= 1000 ->
  clamp_font_weight w = w.
Proof.
  intros w [H1 H2].
  unfold clamp_font_weight.
  assert (Hmin: Z.min 1000 w = w) by (destruct (Z.min_dec 1000 w); lia).
  rewrite Hmin.
  destruct (Z.max_dec 1 w); lia.
Qed.
