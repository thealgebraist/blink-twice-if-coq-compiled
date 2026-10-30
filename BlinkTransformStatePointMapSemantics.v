(* ========================================================================= *)
(*               BlinkTransformStatePointMapSemantics.v                     *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Point Transformation through 2D     *)
(* Affine Matrix against CSS Transforms 1 §5. Fully constructive.            *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record Point2D := mkPt {
  pt_x : Z;
  pt_y : Z
}.

Definition map_point_affine (a b c d e f : Z) (p : Point2D) : Point2D :=
  {| pt_x := a * pt_x p + c * pt_y p + e;
     pt_y := b * pt_x p + d * pt_y p + f |}.

Theorem map_point_affine_identity : forall p,
  map_point_affine 1 0 0 1 0 0 p = p.
Proof.
  intros [x y].
  unfold map_point_affine.
  f_equal; cbv [pt_x pt_y]; ring.
Qed.

Theorem map_point_affine_translation : forall tx ty p,
  map_point_affine 1 0 0 1 tx ty p = {| pt_x := pt_x p + tx; pt_y := pt_y p + ty |}.
Proof.
  intros tx ty [x y].
  unfold map_point_affine.
  f_equal; cbv [pt_x pt_y]; ring.
Qed.
