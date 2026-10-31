(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record PhysicalSize := mkPhysicalSize {
  physicalsize_width : Z;
  physicalsize_height : Z
}.

Definition scale_dimension (dim : Z) (num : Z) (den : Z) : Z :=
  if den <=? 0 then 0 else (dim * num) / den.

Theorem scale_dimension_nonneg :
  forall (dim num den : Z), 0 <= dim -> 0 <= num -> 0 < den -> 0 <= scale_dimension dim num den.
Proof.
  intros dim num den Hdim Hnum Hden.
  unfold scale_dimension.
  destruct (den <=? 0) eqn:Eden.
  - apply Z.leb_le in Eden. lia.
  - apply Z.div_pos; [| lia].
    apply Z.mul_nonneg_nonneg; lia.
Qed.
