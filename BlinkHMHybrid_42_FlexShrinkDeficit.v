(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record FlexShrinkDeficit := mkFlexShrinkDeficit {
  flexshrinkdeficit_base_size : Z;
  flexshrinkdeficit_deficit : Z;
  flexshrinkdeficit_shrink_weight : Z;
  flexshrinkdeficit_total_weight : Z;
  flexshrinkdeficit_min_size : Z
}.

Definition apply_flex_shrink_clamped (base_sz : Z) (deficit : Z) (weight : Z) (total_weight : Z) (min_sz : Z) : Z :=
  Z.max min_sz (base_sz - (deficit * weight) / total_weight).

Theorem flex_shrink_respects_min_and_base :
  forall (base_sz deficit weight total_weight min_sz : Z), min_sz <= base_sz -> 0 <= deficit -> 0 <= weight -> 0 < total_weight -> min_sz <= apply_flex_shrink_clamped base_sz deficit weight total_weight min_sz <= base_sz.
Proof.
  intros base_sz deficit weight total_weight min_sz Hmin Hdef Hw Htw.
  unfold apply_flex_shrink_clamped.
  assert (Hpos : 0 <= (deficit * weight) / total_weight) by (apply Z.div_pos; [nia | lia]).
  lia.
Qed.
