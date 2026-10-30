Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feOffset Translation Semantics *)
(** Filter Effects 1 §10: feOffset translation invariance *)

Record SVGRect := {
  rx : Z;
  ry : Z;
  rw : Z;
  rh : Z
}.

Definition translate_svg_rect (rect : SVGRect) (dx dy : Z) : SVGRect :=
  {| rx := rx rect + dx;
     ry := ry rect + dy;
     rw := rw rect;
     rh := rh rect |}.

Theorem offset_preserves_dimensions : forall rect dx dy,
  rw (translate_svg_rect rect dx dy) = rw rect /\
  rh (translate_svg_rect rect dx dy) = rh rect.
Proof.
  intros rect dx dy.
  destruct rect; simpl; split; reflexivity.
Qed.

Theorem offset_composition_additive : forall rect dx1 dy1 dx2 dy2,
  translate_svg_rect (translate_svg_rect rect dx1 dy1) dx2 dy2 =
  translate_svg_rect rect (dx1 + dx2) (dy1 + dy2).
Proof.
  intros [x y w h] dx1 dy1 dx2 dy2.
  unfold translate_svg_rect; simpl.
  f_equal.
  - lia.
  - lia.
Qed.
