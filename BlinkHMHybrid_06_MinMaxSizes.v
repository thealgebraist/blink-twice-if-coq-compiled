(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record MinMaxSizes := mkMinMaxSizes {
  minmaxsizes_min_size : Z;
  minmaxsizes_max_size : Z
}.

Definition clamp_size (sz : Z) (min_s : Z) (max_s : Z) : Z :=
  if sz <? min_s then min_s else if max_s <? sz then max_s else sz.

Theorem clamp_size_bounded :
  forall (sz min_s max_s : Z), min_s <= max_s -> min_s <= clamp_size sz min_s max_s <= max_s.
Proof.
  intros sz min_s max_s Hle.
  unfold clamp_size.
  destruct (sz <? min_s) eqn:Emin; [apply Z.ltb_lt in Emin; lia |].
  apply Z.ltb_ge in Emin.
  destruct (max_s <? sz) eqn:Emax; [apply Z.ltb_lt in Emax; lia |].
  apply Z.ltb_ge in Emax. lia.
Qed.
