Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Container Query Inline Unit cqi Semantics *)
(** CSS Containment 3 §3: 1cqi = 1% container inline size *)

Definition resolve_cqi (inline_size n_units : Z) : Z :=
  (inline_size * n_units) / 100.

Theorem cqi_positive_units_nonneg : forall s u,
  0 <= s ->
  0 <= u ->
  0 <= resolve_cqi s u.
Proof.
  intros s u Hs Hu.
  unfold resolve_cqi.
  apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia | lia].
Qed.
