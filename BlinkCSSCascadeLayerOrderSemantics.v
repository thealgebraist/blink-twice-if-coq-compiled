Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Cascade Layers @layer Order Semantics *)
(** CSS Cascading 5 §6: layer declaration order strict priority progression *)

Definition layer_priority (layer_idx : Z) : Z :=
  layer_idx + 1.

Theorem layer_priority_strictly_monotonic : forall l,
  l < layer_priority l.
Proof.
  intros l.
  unfold layer_priority; lia.
Qed.
