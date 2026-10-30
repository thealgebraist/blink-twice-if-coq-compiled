Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Flexbox Cross-Axis Stretch Min/Max Clamping Semantics *)
(** CSS Flexbox 1 §9.4: cross-size determination with stretch *)

Definition stretch_cross_size (line_cross min_cross max_cross : Z) : Z :=
  Z.max min_cross (Z.min line_cross max_cross).

Theorem stretch_cross_size_bounded : forall line_cross min_cross max_cross,
  min_cross <= max_cross ->
  min_cross <= stretch_cross_size line_cross min_cross max_cross.
Proof.
  intros line_cross min_cross max_cross Hle.
  unfold stretch_cross_size.
  apply Z.le_max_l.
Qed.
