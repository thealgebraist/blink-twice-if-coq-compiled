Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Property Tree Effect Opacity Product Semantics *)
(** CSS Color 4 §4: opacity composition over [0, 1000] *)

Definition compose_opacity (parent child : Z) : Z :=
  (parent * child) / 1000.

Theorem opacity_nonneg : forall p c,
  0 <= p ->
  0 <= c ->
  0 <= compose_opacity p c.
Proof.
  intros p c Hp Hc.
  unfold compose_opacity.
  apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia | lia].
Qed.

Theorem opacity_bounded_by_parent : forall p c,
  0 <= p ->
  0 <= c ->
  c <= 1000 ->
  compose_opacity p c <= p.
Proof.
  intros p c Hp Hc Hc1.
  unfold compose_opacity.
  apply Z.div_le_upper_bound; [lia |].
  apply Z.le_trans with (p * 1000).
  - apply Z.mul_le_mono_nonneg_l; [exact Hp | exact Hc1].
  - lia.
Qed.
