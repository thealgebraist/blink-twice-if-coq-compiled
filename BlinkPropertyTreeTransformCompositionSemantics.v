Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Property Tree Transform Composition Semantics *)
(** CSS Transforms 2 §2: affine translation vector addition *)

Definition compose_translation (p_tx p_ty c_tx c_ty : Z) : (Z * Z) :=
  (p_tx + c_tx, p_ty + c_ty).

Theorem transform_translation_zero_identity : forall tx ty,
  compose_translation 0 0 tx ty = (tx, ty).
Proof.
  intros tx ty.
  unfold compose_translation; simpl; f_equal; lia.
Qed.

Theorem transform_translation_assoc : forall x1 y1 x2 y2 x3 y3,
  compose_translation (fst (compose_translation x1 y1 x2 y2)) (snd (compose_translation x1 y1 x2 y2)) x3 y3 =
  compose_translation x1 y1 (fst (compose_translation x2 y2 x3 y3)) (snd (compose_translation x2 y2 x3 y3)).
Proof.
  intros x1 y1 x2 y2 x3 y3.
  unfold compose_translation; simpl; f_equal; lia.
Qed.
