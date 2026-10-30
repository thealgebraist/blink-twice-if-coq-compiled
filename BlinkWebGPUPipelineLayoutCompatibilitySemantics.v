Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebGPU Pipeline Layout Binding Compatibility Semantics *)
(** WebGPU §8.1: layout binding type equality *)

Definition binding_compatible (layout_type resource_type : Z) : bool :=
  layout_type =? resource_type.

Theorem binding_compatible_sound : forall l r,
  binding_compatible l r = true <-> l = r.
Proof.
  intros l r.
  unfold binding_compatible.
  apply Z.eqb_eq.
Qed.
