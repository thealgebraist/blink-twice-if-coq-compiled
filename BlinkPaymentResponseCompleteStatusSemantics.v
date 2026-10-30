Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Payment Response Complete Status Semantics *)
(** Payment Request API §6.2: PaymentResponse.complete(result) *)

Inductive response_lifecycle : Type :=
| LifecycleResponding
| LifecycleCompleted (success : bool).

Definition complete_response (s : response_lifecycle) (result : bool) : option response_lifecycle :=
  match s with
  | LifecycleResponding  => Some (LifecycleCompleted result)
  | LifecycleCompleted _ => None
  end.

Theorem complete_cannot_be_called_twice : forall res1 res2,
  complete_response (LifecycleCompleted res1) res2 = None.
Proof.
  intros res1 res2.
  reflexivity.
Qed.
