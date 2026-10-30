Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Shadow DOM Tree Order Cascade Semantics *)
(** CSS Scoping 1 §3: outer tree scopes take precedence for normal declarations *)

Definition shadow_scope_priority (tree_depth : Z) : Z :=
  - tree_depth.

Theorem outer_scope_higher_priority : forall d1 d2,
  d1 < d2 ->
  shadow_scope_priority d2 < shadow_scope_priority d1.
Proof.
  intros d1 d2 H.
  unfold shadow_scope_priority; lia.
Qed.
