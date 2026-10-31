(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record Color := mkColor {
  color_r : Z;
  color_g : Z;
  color_b : Z;
  color_a : Z
}.

Definition alpha_blend (src : Z) (dst : Z) (alpha : Z) : Z :=
  (src * alpha + dst * (255 - alpha)) / 255.

Theorem alpha_blend_opaque_src :
  forall (src dst : Z), 0 <= src <= 255 -> alpha_blend src dst 255 = src.
Proof.
  intros src dst Hsrc.
  unfold alpha_blend.
  replace (255 - 255) with 0 by ring.
  rewrite Z.mul_0_r, Z.add_0_r.
  rewrite Z.div_mul by lia.
  reflexivity.
Qed.
