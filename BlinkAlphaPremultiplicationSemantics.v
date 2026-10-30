Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Alpha Premultiplication Semantics *)
(** Compositing and Blending 1 §3: premultiplied color channel <= original color *)

Definition premultiply_alpha (c a : Z) : Z :=
  (c * a) / 255.

Theorem premultiply_nonneg : forall c a,
  0 <= c ->
  0 <= a ->
  0 <= premultiply_alpha c a.
Proof.
  intros c a Hc Ha.
  unfold premultiply_alpha.
  apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia | lia].
Qed.

Theorem premultiply_bounded_by_color : forall c a,
  0 <= c ->
  0 <= a ->
  a <= 255 ->
  premultiply_alpha c a <= c.
Proof.
  intros c a Hc Ha Ha1.
  unfold premultiply_alpha.
  apply Z.div_le_upper_bound; [lia |].
  apply Z.le_trans with (c * 255).
  - apply Z.mul_le_mono_nonneg_l; [exact Hc | exact Ha1].
  - lia.
Qed.
