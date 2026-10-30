Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Container Query Block Unit cqb Semantics *)
(** CSS Containment 3 §3: 1cqb = 1% container block size *)

Definition resolve_cqb (block_size n_units : Z) : Z :=
  (block_size * n_units) / 100.

Theorem cqb_positive_units_nonneg : forall s u,
  0 <= s ->
  0 <= u ->
  0 <= resolve_cqb s u.
Proof.
  intros s u Hs Hu.
  unfold resolve_cqb.
  apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia | lia].
Qed.
