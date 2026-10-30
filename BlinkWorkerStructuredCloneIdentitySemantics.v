Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Worker Structured Clone Round-Trip Identity Semantics *)
(** HTML Standard §2.7: structured clone serialization/deserialization identity *)

Definition serialize_payload (data : Z) : Z := data.

Definition deserialize_payload (payload : Z) : Z := payload.

Theorem structured_clone_roundtrip_identity : forall d,
  deserialize_payload (serialize_payload d) = d.
Proof.
  intros d.
  reflexivity.
Qed.
