(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record FlexItem := mkFlexItem {
  flexitem_flex_base_size : Z;
  flexitem_flex_grow : Z;
  flexitem_min_size : Z;
  flexitem_max_size : Z
}.

Definition distribute_grow (base : Z) (free_space : Z) (grow : Z) (total_grow : Z) : Z :=
  if total_grow <=? 0 then base else base + (free_space * grow) / total_grow.

Theorem distribute_grow_monotonic :
  forall (base free_space grow total_grow : Z), 0 <= free_space -> 0 <= grow -> 0 < total_grow -> base <= distribute_grow base free_space grow total_grow.
Proof.
  intros base free grow total Hfree Hgrow Htot.
  unfold distribute_grow.
  destruct (total <=? 0) eqn:Etot.
  - apply Z.leb_le in Etot. lia.
  - assert (Hdiv: 0 <= (free * grow) / total).
    { apply Z.div_pos; [| lia]. apply Z.mul_nonneg_nonneg; lia. }
    lia.
Qed.
