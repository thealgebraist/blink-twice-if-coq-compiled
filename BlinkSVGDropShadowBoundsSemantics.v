Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feDropShadow Bounds Expansion Semantics *)
(** Filter Effects 1 §16: feDropShadow bounding box union *)

Record SVGBounds := {
  b_min_x : Z;
  b_min_y : Z;
  b_max_x : Z;
  b_max_y : Z
}.

Definition union_svg_bounds (b1 b2 : SVGBounds) : SVGBounds :=
  {| b_min_x := Z.min (b_min_x b1) (b_min_x b2);
     b_min_y := Z.min (b_min_y b1) (b_min_y b2);
     b_max_x := Z.max (b_max_x b1) (b_max_x b2);
     b_max_y := Z.max (b_max_y b1) (b_max_y b2) |}.

Theorem union_contains_left : forall b1 b2,
  b_min_x (union_svg_bounds b1 b2) <= b_min_x b1 /\
  b_max_x b1 <= b_max_x (union_svg_bounds b1 b2).
Proof.
  intros b1 b2.
  unfold union_svg_bounds; simpl.
  split; lia.
Qed.

Theorem union_contains_right : forall b1 b2,
  b_min_x (union_svg_bounds b1 b2) <= b_min_x b2 /\
  b_max_x b2 <= b_max_x (union_svg_bounds b1 b2).
Proof.
  intros b1 b2.
  unfold union_svg_bounds; simpl.
  split; lia.
Qed.
