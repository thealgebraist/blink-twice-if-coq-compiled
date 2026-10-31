(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record FlexLineState := mkFlexLineState {
  flexlinestate_container_w : Z;
  flexlinestate_used_w : Z;
  flexlinestate_item_count : Z
}.

Definition flex_center_offset (container_w : Z) (used_w : Z) : Z :=
  (Z.max 0 (container_w - used_w)) / 2.

Theorem flex_center_offset_fits_container :
  forall (container_w used_w : Z), 0 <= used_w <= container_w -> 0 <= flex_center_offset container_w used_w /\ flex_center_offset container_w used_w + used_w <= container_w.
Proof.
  intros container_w used_w Hbounds.
  unfold flex_center_offset.
  replace (Z.max 0 (container_w - used_w)) with (container_w - used_w) by lia.
  split.
  - apply Z.div_pos; lia.
  - assert (Hle : (container_w - used_w) / 2 <= container_w - used_w).
    { apply Z.div_le_upper_bound; lia. }
    lia.
Qed.
