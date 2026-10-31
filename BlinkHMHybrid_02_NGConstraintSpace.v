(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record NGConstraintSpace := mkNGConstraintSpace {
  ngconstraintspace_available_inline_size : Z;
  ngconstraintspace_available_block_size : Z;
  ngconstraintspace_percentage_inline_size : Z;
  ngconstraintspace_percentage_block_size : Z
}.

Definition resolve_percentage (pct_base : Z) (pct : Z) : Z :=
  if pct <=? 0 then 0 else (pct_base * pct) / 100.

Theorem resolve_percentage_nonneg :
  forall (pct_base pct : Z), 0 <= pct_base -> 0 <= pct -> 0 <= resolve_percentage pct_base pct.
Proof.
  intros pct_base pct Hbase Hpct.
  unfold resolve_percentage.
  destruct (pct <=? 0) eqn:Epct.
  - lia.
  - apply Z.leb_gt in Epct.
    apply Z.div_pos; [| lia].
    apply Z.mul_nonneg_nonneg; lia.
Qed.
