Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink SVG ClipPath and Mask Intersection Semantics *)
(** SVG 2 §14.3: Clip intersection bounding box containment *)

Record ClipRect := {
  c_left : Z;
  c_right : Z
}.

Definition intersect_clip (r1 r2 : ClipRect) : ClipRect :=
  {| c_left := Z.max (c_left r1) (c_left r2);
     c_right := Z.min (c_right r1) (c_right r2) |}.

Definition clip_width (r : ClipRect) : Z :=
  Z.max 0 (c_right r - c_left r).

Theorem intersect_width_bounded_left : forall r1 r2,
  clip_width (intersect_clip r1 r2) <= clip_width r1.
Proof.
  intros r1 r2.
  unfold clip_width, intersect_clip; simpl.
  lia.
Qed.

Theorem intersect_width_bounded_right : forall r1 r2,
  clip_width (intersect_clip r1 r2) <= clip_width r2.
Proof.
  intros r1 r2.
  unfold clip_width, intersect_clip; simpl.
  lia.
Qed.
