From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.5.3 Table Row Percentage Height Resolution *)
Definition resolve_row_percent_height (table_h : Z) (pct : Z) (min_h : Z) : Z :=
  Z.max min_h ((table_h * pct) / 100).

Theorem row_percent_height_ge_min : forall table_h pct min_h,
  resolve_row_percent_height table_h pct min_h >= min_h.
Proof.
  intros. unfold resolve_row_percent_height. lia.
Qed.

Theorem row_percent_height_monotonic : forall h1 h2 pct min_h,
  0 <= h1 <= h2 ->
  pct >= 0 ->
  resolve_row_percent_height h1 pct min_h <= resolve_row_percent_height h2 pct min_h.
Proof.
  intros h1 h2 pct min_h [Hh1 Hh12] Hpct.
  unfold resolve_row_percent_height.
  assert (Hmul: h1 * pct <= h2 * pct) by (apply Z.mul_le_mono_nonneg_r; lia).
  assert (Hdiv: (h1 * pct) / 100 <= (h2 * pct) / 100) by (apply Z.div_le_mono; lia).
  lia.
Qed.
