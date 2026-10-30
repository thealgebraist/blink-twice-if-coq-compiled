Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink @scope Donut Hole Scoping Semantics *)
(** CSS Cascading 6 §3: scoped styles excluded inside lower boundary limit *)

Definition is_in_donut_scope (in_root in_limit : bool) : bool :=
  andb in_root (negb in_limit).

Theorem donut_scope_includes_when_in_root_not_limit :
  is_in_donut_scope true false = true.
Proof.
  unfold is_in_donut_scope; reflexivity.
Qed.

Theorem donut_scope_excludes_when_in_limit : forall r,
  is_in_donut_scope r true = false.
Proof.
  intros r.
  unfold is_in_donut_scope; simpl.
  apply andb_false_r.
Qed.
