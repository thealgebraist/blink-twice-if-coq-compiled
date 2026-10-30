Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Subgrid Line Name Inheritance Semantics *)
(** CSS Grid 2 §2: line names inherited within spanned range *)

Definition is_line_name_in_subgrid (line_idx subgrid_start subgrid_end : Z) : bool :=
  andb (subgrid_start <=? line_idx) (line_idx <=? subgrid_end).

Theorem subgrid_contains_within_bounds : forall l s e,
  s <= l ->
  l <= e ->
  is_line_name_in_subgrid l s e = true.
Proof.
  intros l s e Hs He.
  unfold is_line_name_in_subgrid.
  apply andb_true_iff; split; apply Z.leb_le; lia.
Qed.

Theorem subgrid_excludes_outside_bounds : forall l s e,
  l < s ->
  is_line_name_in_subgrid l s e = false.
Proof.
  intros l s e H.
  unfold is_line_name_in_subgrid.
  apply andb_false_iff; left.
  apply Z.leb_gt; lia.
Qed.
