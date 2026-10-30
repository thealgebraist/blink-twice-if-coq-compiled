Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Fetch Headers Guard Mutation Semantics *)
(** Fetch Standard §2.2: Headers guard states and immutable guard protection *)

Definition GUARD_NONE             : Z := 0.
Definition GUARD_REQUEST          : Z := 1.
Definition GUARD_REQUEST_NO_CORS  : Z := 2.
Definition GUARD_RESPONSE         : Z := 3.
Definition GUARD_IMMUTABLE        : Z := 4.

Definition guard_allows_mutation (guard : Z) : bool :=
  negb (guard =? GUARD_IMMUTABLE).

Theorem immutable_guard_forbids_mutation :
  guard_allows_mutation GUARD_IMMUTABLE = false.
Proof.
  reflexivity.
Qed.

Theorem mutable_guards_allow_mutation : forall g,
  g <> GUARD_IMMUTABLE ->
  guard_allows_mutation g = true.
Proof.
  intros g Hg.
  unfold guard_allows_mutation.
  apply Z.eqb_neq in Hg.
  rewrite Hg.
  reflexivity.
Qed.
