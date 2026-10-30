Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Sequential Focus Tabindex Ordering Semantics *)
(** HTML Standard §7.3: positive tabindex prioritized over zero/negative *)

Definition tabindex_class (tabindex : Z) : Z :=
  if 0 <? tabindex then 2
  else if tabindex =? 0 then 1
  else 0.

Theorem positive_tabindex_higher_class : forall t,
  0 < t ->
  tabindex_class 0 < tabindex_class t.
Proof.
  intros t Ht.
  change (tabindex_class 0) with 1.
  unfold tabindex_class.
  apply Z.ltb_lt in Ht.
  rewrite Ht.
  lia.
Qed.
