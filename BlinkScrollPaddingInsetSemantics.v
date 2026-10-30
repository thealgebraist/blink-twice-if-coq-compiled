Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Padding Inset Semantics *)
(** CSS Scroll Snap 1 §5: snapport shrinkage *)

Definition shrink_snapport (port_dim padding : Z) : Z :=
  Z.max 0 (port_dim - 2 * Z.max 0 padding).

Theorem snapport_shrinkage_bounded : forall port p,
  shrink_snapport port p <= Z.max 0 port.
Proof.
  intros port p.
  unfold shrink_snapport.
  lia.
Qed.
