Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink DOMTokenList Class Uniqueness Semantics *)
(** DOM Standard §7.1: token set uniqueness on duplicate insertion *)

Definition add_token_unique (already_present : bool) (count : Z) : Z :=
  if already_present then count else count + 1.

Theorem existing_token_preserves_count : forall c,
  add_token_unique true c = c.
Proof.
  intros c; reflexivity.
Qed.

Theorem new_token_increments_count : forall c,
  add_token_unique false c = c + 1.
Proof.
  intros c; reflexivity.
Qed.
