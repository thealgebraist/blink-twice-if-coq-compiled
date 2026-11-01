(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record BoxShadowBlurFalloff := mkBoxShadowBlurFalloff {
  boxshadowblurfalloff_base_alpha : Z;
  boxshadowblurfalloff_edge_dist : Z;
  boxshadowblurfalloff_blur_radius : Z
}.

Definition shadow_blur_alpha (base_a : Z) (dist : Z) (blur : Z) : Z :=
  if blur <=? 0 then (if dist <=? 0 then base_a else 0) else if dist <=? 0 then base_a else if blur <=? dist then 0 else (base_a * (blur - dist)) / blur.

Theorem shadow_blur_alpha_within_base :
  forall (base_a dist blur : Z), 0 <= base_a <= 255 -> 0 <= shadow_blur_alpha base_a dist blur <= base_a.
Proof.
  intros base_a dist blur Ha. unfold shadow_blur_alpha.
  destruct (blur <=? 0) eqn:Eb.
  - destruct (dist <=? 0); lia.
  - apply Z.leb_gt in Eb.
    destruct (dist <=? 0) eqn:Ed.
    + lia.
    + apply Z.leb_gt in Ed.
      destruct (blur <=? dist) eqn:Ebd.
      * lia.
      * apply Z.leb_gt in Ebd. split.
        -- apply Z.div_pos; [nia | lia].
        -- apply Z.div_le_upper_bound; [lia | nia].
Qed.
