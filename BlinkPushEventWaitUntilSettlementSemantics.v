Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Push Event WaitUntil Promise Settlement Semantics *)
(** Service Worker §4.3: ExtendableEvent.waitUntil pending promise tracking *)

Definition extend_lifetime (pending : Z) : Z :=
  pending + 1.

Definition settle_promise (pending : Z) : Z :=
  if pending <=? 1 then 0 else pending - 1.

Theorem extend_then_settle : forall pending,
  pending >= 0 ->
  settle_promise (extend_lifetime pending) = pending.
Proof.
  intros pending H.
  unfold extend_lifetime, settle_promise.
  destruct (pending + 1 <=? 1) eqn:E.
  - apply Z.leb_le in E. lia.
  - apply Z.leb_gt in E. lia.
Qed.
