Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink ID Invalidation Propagation Semantics *)
(** Blink Style Invalidation §2: invalidation propagates to descendants *)

Definition propagate_id_invalidation (depth : Z) : Z :=
  depth + 1.

Theorem invalidation_depth_strictly_monotonic : forall d,
  d < propagate_id_invalidation d.
Proof.
  intros d.
  unfold propagate_id_invalidation; lia.
Qed.
