Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feColorMatrix 5x4 Affine Color Transform Semantics *)
(** Filter Effects 1 §9: feColorMatrix channel clamping into [0, 255] *)

Record RGBAColor := {
  red : Z;
  green : Z;
  blue : Z;
  alpha : Z
}.

Definition clamp255 (v : Z) : Z :=
  Z.max 0 (Z.min 255 v).

Definition apply_identity_color_matrix (c : RGBAColor) : RGBAColor :=
  {| red := clamp255 (red c);
     green := clamp255 (green c);
     blue := clamp255 (blue c);
     alpha := clamp255 (alpha c) |}.

Theorem clamp255_bounds : forall v,
  0 <= clamp255 v <= 255.
Proof.
  intros v.
  unfold clamp255.
  lia.
Qed.

Theorem identity_matrix_preserves_valid_color : forall c,
  0 <= red c <= 255 ->
  0 <= green c <= 255 ->
  0 <= blue c <= 255 ->
  0 <= alpha c <= 255 ->
  apply_identity_color_matrix c = c.
Proof.
  intros c Hr Hg Hb Ha.
  unfold apply_identity_color_matrix, clamp255.
  destruct c as [r g b a]; simpl in *.
  assert (Z.max 0 (Z.min 255 r) = r) by lia.
  assert (Z.max 0 (Z.min 255 g) = g) by lia.
  assert (Z.max 0 (Z.min 255 b) = b) by lia.
  assert (Z.max 0 (Z.min 255 a) = a) by lia.
  rewrite H, H0, H1, H2.
  reflexivity.
Qed.
