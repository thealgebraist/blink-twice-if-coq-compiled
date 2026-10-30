Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Event composedPath Traversal Semantics *)
(** DOM Standard §2.8: uncomposed event halts at shadow boundary *)

Definition traverse_boundary (is_composed : bool) (current_depth : Z) : Z :=
  if is_composed then current_depth + 1 else current_depth.

Theorem uncomposed_event_halts_at_boundary : forall d,
  traverse_boundary false d = d.
Proof.
  intros d; reflexivity.
Qed.

Theorem composed_event_crosses_boundary : forall d,
  d < traverse_boundary true d.
Proof.
  intros d.
  unfold traverse_boundary; lia.
Qed.
