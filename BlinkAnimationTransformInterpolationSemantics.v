Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Transform Interpolation Semantics *)
(** CSS Transforms 2 §4: 2D translation interpolation *)

Record Translation2D := {
  tx : Z;
  ty : Z
}.

Definition lerp_translation (t0 t1 : Translation2D) (prog : Z) : Translation2D :=
  {| tx := tx t0 + (tx t1 - tx t0) * prog / 1000;
     ty := ty t0 + (ty t1 - ty t0) * prog / 1000 |}.

Theorem lerp_translation_start : forall t0 t1,
  lerp_translation t0 t1 0 = t0.
Proof.
  intros [x0 y0] [x1 y1].
  unfold lerp_translation; simpl.
  assert ((x1 - x0) * 0 / 1000 = 0) by (rewrite Z.mul_0_r; reflexivity).
  assert ((y1 - y0) * 0 / 1000 = 0) by (rewrite Z.mul_0_r; reflexivity).
  rewrite H, H0.
  f_equal; lia.
Qed.

Theorem lerp_translation_end : forall t0 t1,
  lerp_translation t0 t1 1000 = t1.
Proof.
  intros [x0 y0] [x1 y1].
  unfold lerp_translation; simpl.
  rewrite !Z.div_mul by lia.
  f_equal; lia.
Qed.
