Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Opaque Origin Uniqueness Semantics *)
(** HTML Standard §7.5: Opaque origins are distinct by unguessable nonce id *)

Definition opaque_origin_eq (id1 id2 : Z) : bool :=
  id1 =? id2.

Theorem opaque_origins_distinct : forall id1 id2,
  id1 <> id2 ->
  opaque_origin_eq id1 id2 = false.
Proof.
  intros id1 id2 Hneq.
  unfold opaque_origin_eq.
  apply Z.eqb_neq.
  assumption.
Qed.

Theorem opaque_origins_refl : forall id,
  opaque_origin_eq id id = true.
Proof.
  intros id.
  unfold opaque_origin_eq.
  apply Z.eqb_refl.
Qed.
