Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink SharedWorker MessagePort Entanglement Invariance *)
(** HTML Standard §10.3: entangled port pairs form an involution *)

Definition entangled_port (port_id : Z) : Z :=
  if port_id =? 1 then 2
  else if port_id =? 2 then 1
  else 0.

Theorem entanglement_involutive_port1 :
  entangled_port (entangled_port 1) = 1.
Proof.
  reflexivity.
Qed.

Theorem entanglement_involutive_port2 :
  entangled_port (entangled_port 2) = 2.
Proof.
  reflexivity.
Qed.
