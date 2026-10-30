Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink PointerEvent Identifier & Primary Pointer Semantics *)
(** Pointer Events 3 §5: primary pointer tracking *)

Definition is_primary_pointer (active_pointers : Z) (is_first_pointer : bool) : bool :=
  is_first_pointer && (active_pointers =? 1).

Theorem primary_requires_single_pointer : forall act is_first,
  is_primary_pointer act is_first = true ->
  act = 1.
Proof.
  intros act is_first H.
  unfold is_primary_pointer in H.
  apply andb_prop in H.
  destruct H as [_ Hact].
  apply Z.eqb_eq in Hact.
  exact Hact.
Qed.
