(* ========================================================================= *)
(*               BlinkBlockHeightClampingSemantics.v                         *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Block Height Clamping (min-height,      *)
(* max-height) per W3C CSS 2.1 §10.6.4 & CSS Sizing 3 §5.                    *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition clamp_block_height (min_h max_h h : Z) : Z :=
  Z.max min_h (Z.min max_h h).

Theorem clamp_height_ge_min : forall min_h max_h h,
  clamp_block_height min_h max_h h >= min_h.
Proof.
  intros. unfold clamp_block_height.
  apply Z.le_ge, Z.le_max_l.
Qed.

Theorem clamp_height_le_max_when_valid : forall min_h max_h h,
  min_h <= max_h ->
  clamp_block_height min_h max_h h <= max_h.
Proof.
  intros min_h max_h h Hle.
  unfold clamp_block_height.
  apply Z.max_lub_iff.
  split; [assumption | apply Z.le_min_l].
Qed.

Theorem clamp_height_min_wins_over_max : forall min_h max_h h,
  min_h > max_h ->
  clamp_block_height min_h max_h h = min_h.
Proof.
  intros min_h max_h h Hgt.
  unfold clamp_block_height.
  apply Z.max_l.
  pose proof (Z.le_min_l max_h h).
  lia.
Qed.

Theorem clamp_height_monotonic : forall min_h max_h h1 h2,
  h1 <= h2 ->
  clamp_block_height min_h max_h h1 <= clamp_block_height min_h max_h h2.
Proof.
  intros min_h max_h h1 h2 Hle.
  unfold clamp_block_height.
  destruct (Z.min_spec max_h h1) as [[_ Hmin1] | [_ Hmin1]];
  destruct (Z.min_spec max_h h2) as [[_ Hmin2] | [_ Hmin2]];
  rewrite Hmin1, Hmin2; lia.
Qed.
