Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink File System Remove Recursive Safety Semantics *)
(** File System Access API §6: removeEntry non-recursive requires empty directory *)

Definition can_remove_entry (is_empty recursive : bool) : bool :=
  is_empty || recursive.

Theorem non_empty_requires_recursive : forall is_empty recursive,
  is_empty = false ->
  can_remove_entry is_empty recursive = true ->
  recursive = true.
Proof.
  intros is_empty recursive Hempty Hcan.
  unfold can_remove_entry in Hcan.
  rewrite Hempty in Hcan.
  simpl in Hcan.
  exact Hcan.
Qed.
