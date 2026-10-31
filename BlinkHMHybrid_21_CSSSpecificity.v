(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CSSSpecificity := mkCSSSpecificity {
  cssspecificity_id_cnt : Z;
  cssspecificity_class_cnt : Z;
  cssspecificity_tag_cnt : Z
}.

Definition pack_specificity_clamped (id_c : Z) (cls_c : Z) (tag_c : Z) : Z :=
  id_c * 65536 + cls_c * 256 + tag_c.

Theorem pack_specificity_id_dominates_bounded_class_tag :
  forall (i1 c1 t1 i2 c2 t2 : Z), 0 <= c1 < 256 -> 0 <= t1 < 256 -> 0 <= c2 < 256 -> 0 <= t2 < 256 -> i1 < i2 -> pack_specificity_clamped i1 c1 t1 < pack_specificity_clamped i2 c2 t2.
Proof.
  intros i1 c1 t1 i2 c2 t2 Hc1 Ht1 Hc2 Ht2 Hi.
  unfold pack_specificity_clamped. lia.
Qed.
