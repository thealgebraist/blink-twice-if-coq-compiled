From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Transforms 1 §5 2D Translation Composition *)
Record Translation2D := {
  t2d_x : Z;
  t2d_y : Z
}.

Definition concat_translations (t1 t2 : Translation2D) : Translation2D :=
  {| t2d_x := t2d_x t1 + t2d_x t2;
     t2d_y := t2d_y t1 + t2d_y t2 |}.

Definition zero_translation : Translation2D :=
  {| t2d_x := 0; t2d_y := 0 |}.

Theorem concat_translations_identity_left : forall t,
  concat_translations zero_translation t = t.
Proof.
  intros [x y].
  unfold concat_translations, zero_translation; cbn.
  f_equal; lia.
Qed.

Theorem concat_translations_identity_right : forall t,
  concat_translations t zero_translation = t.
Proof.
  intros [x y].
  unfold concat_translations, zero_translation; cbn.
  f_equal; lia.
Qed.

Theorem concat_translations_comm : forall t1 t2,
  concat_translations t1 t2 = concat_translations t2 t1.
Proof.
  intros [x1 y1] [x2 y2].
  unfold concat_translations; cbn.
  f_equal; lia.
Qed.
