Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Subscript Drop Semantics *)
(** MathML Core §3.4.1: subscript baseline drop >= min_drop *)

Definition resolve_subscript_drop (desired_drop min_drop : Z) : Z :=
  Z.max (Z.max 0 min_drop) desired_drop.

Theorem subscript_drop_ge_min : forall des min_d,
  0 <= min_d ->
  min_d <= resolve_subscript_drop des min_d.
Proof.
  intros des min_d Hmin.
  unfold resolve_subscript_drop.
  lia.
Qed.
