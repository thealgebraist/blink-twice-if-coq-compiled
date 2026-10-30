(* ========================================================================= *)
(*               BlinkBlockWidthClampingSemantics.v                          *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Block Width Clamping (min-width,       *)
(* max-width) per W3C CSS 2.1 §10.4 & CSS Sizing 3 §5.                       *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition clamp_block_width (min_w max_w w : Z) : Z :=
  Z.max min_w (Z.min max_w w).

Theorem clamp_width_ge_min : forall min_w max_w w,
  clamp_block_width min_w max_w w >= min_w.
Proof.
  intros. unfold clamp_block_width.
  apply Z.le_ge, Z.le_max_l.
Qed.

Theorem clamp_width_le_max_when_valid : forall min_w max_w w,
  min_w <= max_w ->
  clamp_block_width min_w max_w w <= max_w.
Proof.
  intros min_w max_w w Hle.
  unfold clamp_block_width.
  apply Z.max_lub_iff.
  split; [assumption | apply Z.le_min_l].
Qed.

Theorem clamp_width_min_wins_over_max : forall min_w max_w w,
  min_w > max_w ->
  clamp_block_width min_w max_w w = min_w.
Proof.
  intros min_w max_w w Hgt.
  unfold clamp_block_width.
  apply Z.max_l.
  pose proof (Z.le_min_l max_w w).
  lia.
Qed.

Theorem clamp_width_monotonic : forall min_w max_w w1 w2,
  w1 <= w2 ->
  clamp_block_width min_w max_w w1 <= clamp_block_width min_w max_w w2.
Proof.
  intros min_w max_w w1 w2 Hle.
  unfold clamp_block_width.
  destruct (Z.min_spec max_w w1) as [[_ Hmin1] | [_ Hmin1]];
  destruct (Z.min_spec max_w w2) as [[_ Hmin2] | [_ Hmin2]];
  rewrite Hmin1, Hmin2; lia.
Qed.
