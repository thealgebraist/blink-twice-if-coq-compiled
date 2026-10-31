(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CascadePriority := mkCascadePriority {
  cascadepriority_origin_rank : Z;
  cascadepriority_is_important : bool;
  cascadepriority_layer_order : Z;
  cascadepriority_source_order : Z
}.

Definition effective_layer_key (is_important : bool) (layer_order : Z) : Z :=
  if is_important then 65535 - layer_order else layer_order.

Theorem effective_layer_key_important_inverts :
  forall (l1 l2 : Z), l1 < l2 -> effective_layer_key false l1 < effective_layer_key false l2 /\ effective_layer_key true l2 < effective_layer_key true l1.
Proof.
  intros l1 l2 Hlt. unfold effective_layer_key. lia.
Qed.
