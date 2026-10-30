Require Import ZArith.
Require Import Lia.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink DedicatedWorker FIFO Task Queue Semantics *)
(** HTML Standard §10.2: FIFO execution ordering *)

Definition dequeue_task (q : list Z) : option (Z * list Z) :=
  match q with
  | [] => None
  | t :: rest => Some (t, rest)
  end.

Theorem enqueue_dequeue_fifo_head : forall t rest,
  dequeue_task (t :: rest) = Some (t, rest).
Proof.
  intros t rest.
  reflexivity.
Qed.

Theorem fifo_order_preserved_on_append : forall t rest x,
  dequeue_task (t :: (rest ++ [x])) = Some (t, rest ++ [x]).
Proof.
  intros t rest x.
  reflexivity.
Qed.
