Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Line Box Half-Leading Distribution Semantics *)
(** CSS 2.1 §10.8.1: half-leading distribution *)

Definition adjusted_ascent (font_asc half_leading : Z) : Z :=
  font_asc + half_leading.

Definition adjusted_descent (font_desc half_leading : Z) : Z :=
  font_desc + half_leading.

Theorem line_extent_conservation : forall font_asc font_desc half_leading,
  adjusted_ascent font_asc half_leading + adjusted_descent font_desc half_leading =
  font_asc + font_desc + 2 * half_leading.
Proof.
  intros font_asc font_desc half_leading.
  unfold adjusted_ascent, adjusted_descent.
  lia.
Qed.
