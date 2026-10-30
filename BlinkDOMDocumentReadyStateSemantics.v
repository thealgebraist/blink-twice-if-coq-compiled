Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Document readyState Progression Semantics *)
(** HTML Standard §7.4: loading(1) -> interactive(2) -> complete(3) *)

Inductive ReadyState :=
  | ReadyLoading
  | ReadyInteractive
  | ReadyComplete.

Definition ready_num (r : ReadyState) : Z :=
  match r with
  | ReadyLoading => 1
  | ReadyInteractive => 2
  | ReadyComplete => 3
  end.

Theorem ready_state_monotonic_step1 :
  ready_num ReadyLoading < ready_num ReadyInteractive.
Proof.
  unfold ready_num; lia.
Qed.

Theorem ready_state_monotonic_step2 :
  ready_num ReadyInteractive < ready_num ReadyComplete.
Proof.
  unfold ready_num; lia.
Qed.
