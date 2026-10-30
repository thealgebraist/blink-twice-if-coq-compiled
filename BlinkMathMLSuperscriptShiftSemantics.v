Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Superscript Shift Semantics *)
(** MathML Core §3.4.1: superscript baseline shift >= min_shift *)

Definition resolve_superscript_shift (desired_shift min_shift : Z) : Z :=
  Z.max (Z.max 0 min_shift) desired_shift.

Theorem superscript_shift_ge_min : forall des min_s,
  0 <= min_s ->
  min_s <= resolve_superscript_shift des min_s.
Proof.
  intros des min_s Hmin.
  unfold resolve_superscript_shift.
  lia.
Qed.
