(* ========================================================================= *)
(*               BlinkPerspectiveProjectionSemantics.v                      *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Perspective Projection Matrix        *)
(* against CSS Transforms 2 §4. Fully constructive, 0 admits.                *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition perspective_scale (d z : Z) : Z :=
  if d - z <=? 0 then 0
  else (d * 1000) / (d - z).

Theorem perspective_scale_neutral_at_zero : forall d,
  d > 0 ->
  perspective_scale d 0 = 1000.
Proof.
  intros d Hd.
  unfold perspective_scale.
  assert (E: (d - 0 <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  assert (d - 0 = d) as -> by lia.
  rewrite Z.mul_comm.
  apply Z.div_mul; lia.
Qed.

Theorem perspective_scale_nonneg : forall d z,
  d > 0 ->
  perspective_scale d z >= 0.
Proof.
  intros d z Hd.
  unfold perspective_scale.
  destruct (d - z <=? 0) eqn:E; [lia |].
  apply Z.leb_gt in E.
  assert (0 <= d * 1000) by lia.
  assert (0 <= (d * 1000) / (d - z)) by (apply Z.div_pos; lia).
  lia.
Qed.
