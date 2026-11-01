(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record StackingZOrder := mkStackingZOrder {
  stackingzorder_z_index : Z;
  stackingzorder_dom_order : Z
}.

Definition pack_stacking_key (z_idx : Z) (dom_ord : Z) : Z :=
  (z_idx + 32768) * 65536 + dom_ord.

Theorem higher_z_index_strictly_dominates_dom_order :
  forall (z1 z2 d1 d2 : Z), -32768 <= z1 -> z1 < z2 -> z2 <= 32767 -> 0 <= d1 < 65536 -> 0 <= d2 < 65536 -> pack_stacking_key z1 d1 < pack_stacking_key z2 d2.
Proof.
  intros z1 z2 d1 d2 Hz1 Hlt Hz2 Hd1 Hd2. unfold pack_stacking_key. lia.
Qed.
