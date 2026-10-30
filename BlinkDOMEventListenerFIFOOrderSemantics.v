Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink EventListener Invocation Order Semantics *)
(** DOM Standard §2.6: registration FIFO order sequence progression *)

Definition next_listener_seq (seq : Z) : Z :=
  seq + 1.

Theorem listener_order_strictly_increasing : forall s,
  s < next_listener_seq s.
Proof.
  intros s.
  unfold next_listener_seq; lia.
Qed.
