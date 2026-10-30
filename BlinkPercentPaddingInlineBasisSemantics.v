From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Box Model 3 §6 Percentage Padding Resolves Against Inline Size *)
Definition resolve_percent_padding (cb_inline_size : Z) (pct : Z) : Z :=
  (cb_inline_size * pct) / 100.

Theorem percent_padding_nonneg : forall cb_inline pct,
  cb_inline >= 0 ->
  pct >= 0 ->
  resolve_percent_padding cb_inline pct >= 0.
Proof.
  intros cb pct Hcb Hpct.
  unfold resolve_percent_padding.
  assert (0 <= (cb * pct) / 100).
  { apply Z.div_le_lower_bound; lia. }
  lia.
Qed.

Theorem percent_padding_monotonic : forall cb1 cb2 pct,
  0 <= cb1 <= cb2 ->
  pct >= 0 ->
  resolve_percent_padding cb1 pct <= resolve_percent_padding cb2 pct.
Proof.
  intros cb1 cb2 pct [Hcb1 Hcb12] Hpct.
  unfold resolve_percent_padding.
  assert (Hmul: cb1 * pct <= cb2 * pct) by (apply Z.mul_le_mono_nonneg_r; lia).
  apply Z.div_le_mono; lia.
Qed.
