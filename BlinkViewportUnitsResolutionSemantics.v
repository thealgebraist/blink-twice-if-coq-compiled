From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Values 4 §6.1 Viewport Units Resolution *)
Definition resolve_vw (vw_count : Z) (viewport_w : Z) : Z :=
  (vw_count * viewport_w) / 100.

Theorem full_viewport_width_exact : forall v_w,
  resolve_vw 100 v_w = v_w.
Proof.
  intros v_w.
  unfold resolve_vw.
  rewrite (Z.mul_comm 100 v_w).
  apply Z.div_mul. lia.
Qed.

Theorem vw_nonneg : forall count v_w,
  count >= 0 ->
  v_w >= 0 ->
  resolve_vw count v_w >= 0.
Proof.
  intros count v_w Hc Hv.
  unfold resolve_vw.
  assert (0 <= (count * v_w) / 100).
  { apply Z.div_le_lower_bound; lia. }
  lia.
Qed.
