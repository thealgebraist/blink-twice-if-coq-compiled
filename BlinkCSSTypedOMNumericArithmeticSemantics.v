Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Typed OM Numeric Value Arithmetic Semantics *)
(** CSS Typed OM 1 §3: numeric value arithmetic and algebraic identity *)

Definition add_typed_numeric (v1 v2 : Z) : Z :=
  v1 + v2.

Theorem typed_numeric_add_zero_identity : forall v,
  add_typed_numeric v 0 = v.
Proof.
  intros v.
  unfold add_typed_numeric; lia.
Qed.

Theorem typed_numeric_add_comm : forall v1 v2,
  add_typed_numeric v1 v2 = add_typed_numeric v2 v1.
Proof.
  intros v1 v2.
  unfold add_typed_numeric; lia.
Qed.
