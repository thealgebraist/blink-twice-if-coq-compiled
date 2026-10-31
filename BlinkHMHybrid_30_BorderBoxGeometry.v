(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record BorderBoxGeometry := mkBorderBoxGeometry {
  borderboxgeometry_specified_w : Z;
  borderboxgeometry_pad_h : Z;
  borderboxgeometry_bdr_h : Z;
  borderboxgeometry_is_border_box : bool
}.

Definition border_box_content_width (is_border_box : bool) (spec_w : Z) (pad_h : Z) (bdr_h : Z) : Z :=
  if is_border_box then Z.max 0 (spec_w - pad_h - bdr_h) else Z.max 0 spec_w.

Theorem border_box_outer_width_exact :
  forall (spec_w pad_h bdr_h : Z), 0 <= pad_h -> 0 <= bdr_h -> pad_h + bdr_h <= spec_w -> border_box_content_width true spec_w pad_h bdr_h + pad_h + bdr_h = spec_w.
Proof.
  intros spec_w pad_h bdr_h Hp Hb Hfit.
  unfold border_box_content_width. simpl. lia.
Qed.
