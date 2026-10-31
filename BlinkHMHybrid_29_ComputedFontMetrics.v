(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record ComputedFontMetrics := mkComputedFontMetrics {
  computedfontmetrics_font_px : Z;
  computedfontmetrics_parent_px : Z;
  computedfontmetrics_root_px : Z
}.

Definition resolve_em_or_rem (is_rem : bool) (mult : Z) (parent_px : Z) (root_px : Z) : Z :=
  if is_rem then mult * root_px else mult * parent_px.

Theorem resolve_em_or_rem_nonneg :
  forall (is_rem : bool) (mult parent_px root_px : Z), 0 <= mult -> 0 <= parent_px -> 0 <= root_px -> 0 <= resolve_em_or_rem is_rem mult parent_px root_px.
Proof.
  intros is_rem mult parent_px root_px Hm Hp Hr.
  unfold resolve_em_or_rem.
  destruct is_rem; apply Z.mul_nonneg_nonneg; lia.
Qed.
