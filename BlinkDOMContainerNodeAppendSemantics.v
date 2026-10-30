Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink ContainerNode appendChild Semantics *)
(** DOM Standard §4.2.3: appendChild strictly increments childNodes length *)

Definition append_child_count (cur : Z) : Z :=
  cur + 1.

Theorem append_child_count_strictly_monotonic : forall c,
  c < append_child_count c.
Proof.
  intros c.
  unfold append_child_count; lia.
Qed.
