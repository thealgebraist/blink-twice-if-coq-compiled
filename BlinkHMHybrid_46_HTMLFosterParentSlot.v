(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record HTMLFosterParentSlot := mkHTMLFosterParentSlot {
  htmlfosterparentslot_parent_child_count : Z;
  htmlfosterparentslot_table_child_index : Z
}.

Definition foster_insert_index (parent_cnt : Z) (table_idx : Z) : Z :=
  if table_idx <? 0 then parent_cnt else Z.min parent_cnt table_idx.

Theorem foster_insert_index_valid_slot :
  forall (parent_cnt table_idx : Z), 0 <= parent_cnt -> 0 <= foster_insert_index parent_cnt table_idx <= parent_cnt.
Proof.
  intros parent_cnt table_idx Hcnt. unfold foster_insert_index.
  destruct (table_idx <? 0) eqn:Elt.
  - lia.
  - apply Z.ltb_ge in Elt. lia.
Qed.
