(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record OutOfFlowInset := mkOutOfFlowInset {
  outofflowinset_cb_size : Z;
  outofflowinset_inset_start : Z;
  outofflowinset_inset_end : Z
}.

Definition oof_stretch_size (cb_size : Z) (inset_start : Z) (inset_end : Z) : Z :=
  Z.max 0 (cb_size - inset_start - inset_end).

Theorem oof_stretch_fills_containing_block :
  forall (cb_size inset_start inset_end : Z), inset_start + inset_end <= cb_size -> inset_start + oof_stretch_size cb_size inset_start inset_end + inset_end = cb_size.
Proof.
  intros cb_size inset_start inset_end Hle. unfold oof_stretch_size. lia.
Qed.
